<#
L05 (test plan): the export and collector logic in Pester 5, under Windows PowerShell 5.1 (P25), synthetic data only.
Runs on a lab VM from the scratch folder C:\BbDev (P24) or on the CI Windows runner; never touches the real
collector, the real C:\ProgramData\PerfmonBlackbox or any scheduled task: the paths are redirected to TestDrive and
the upload is a script block. Needs relog.exe (Windows) to turn synthetic CSVs into .blg files.

  Invoke-Pester -Path tests\pester -Output Detailed      (from playbooks\perfmon-blackbox)
#>
BeforeAll {
    $PB = Resolve-Path (Join-Path $PSScriptRoot '..\..')
    . (Join-Path $PB 'package\scripts\PerfmonBlackbox.Common.ps1')
    $script:Collector = Join-Path $PB 'package\collector'
    $script:Base36 = @(Read-BbCounterFile (Join-Path $script:Collector 'PerfmonBlackbox.counters.txt'))

    function New-TestCsv {
        # a small synthetic PDH-CSV with the 36 counters (one instance each), one row per $Step seconds
        param([string]$Path, [datetime]$Start, [int]$Rows, [int]$Step = 10, [int[]]$Skip = @())
        $cols = $script:Base36 | ForEach-Object { '\\SYNTH01' + ($_ -replace '\(\*\)', '(_Total)') }
        $lines = @('"(PDH-CSV 4.0) (Coordinated Universal Time)(0)","' + ($cols -join '","') + '"')
        for ($i = 0; $i -lt $Rows; $i++) {
            if ($Skip -contains $i) { continue }
            $t = $Start.AddSeconds($i * $Step).ToString('MM/dd/yyyy HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
            $lines += '"' + $t + '","' + ((1..$cols.Count | ForEach-Object { $i + $_ }) -join '","') + '"'
        }
        [IO.File]::WriteAllLines($Path, $lines)
    }

    function New-TestBlg {
        # relog turns the CSV into a binary log, as PLA would have written it
        param([string]$Csv, [string]$Blg)
        $r = Invoke-BbTool relog.exe @($Csv, '-f', 'bin', '-o', $Blg, '-y')
        if ($r.ExitCode -ne 0) { throw "relog csv->blg failed: $($r.Output -join ' ')" }
    }

    function Use-TestRoot {
        param([string]$Root)
        $script:BbRoot = $Root
        $p = Get-BbPaths
        foreach ($d in $p.Root, $p.Bin, $p.Blg, $p.Pending, $p.Work, $p.Outbox, $p.Log) { $null = New-Item -ItemType Directory -Force -Path $d }
        Write-BbJson $p.Config ([ordered]@{ MaxSizeMB = 512; SampleIntervalSeconds = 10; ExportEveryHours = 4
            StorageAccountResourceId = '/subscriptions/synthsub/resourceGroups/rg-synth/providers/Microsoft.Storage/storageAccounts/stsynth'
            ContainerName = 'perfmon'; LocalKeepMB = 1024 })
        return $p
    }

    $script:Machine = [pscustomobject]@{ Kind = 'imds'; SubscriptionId = 'synthsub'; ResourceGroup = 'rg-synth'; Name = 'SYNTH01'
        ResourceId = '/subscriptions/synthsub/resourceGroups/rg-synth/providers/Microsoft.Compute/virtualMachines/SYNTH01'; Prefix = 'synthsub/rg-synth/synth01' }
    $script:Uploads = New-Object System.Collections.ArrayList
    $script:OkUploader = { param($blob, $zip, $meta) $null = $script:Uploads.Add(@{ blob = $blob; meta = $meta; bytes = (Get-Item $zip).Length }); 201 }
    $script:FailUploader = { param($blob, $zip, $meta) throw 'storage unreachable (test)' }
    Mock Write-BbEvent { }
}

Describe 'PDH CSV helpers' {
    It 'splits and joins a quoted row, commas inside instance names kept' {
        $f = Split-BbCsvLine '"a","\\H\Processor Information(0,1)\% Processor Time","3"'
        $f.Count | Should -Be 3
        $f[1] | Should -Be '\\H\Processor Information(0,1)\% Processor Time'
        Join-BbCsvLine $f | Should -Be '"a","\\H\Processor Information(0,1)\% Processor Time","3"'
    }
    It 'detects day-first and month-first' {
        Get-BbTimeFormat @('13/10/2026 08:00:00.000') | Should -Be 'dd/MM/yyyy HH:mm:ss.fff'
        Get-BbTimeFormat @('10/13/2026 08:00:00.000') | Should -Be 'MM/dd/yyyy HH:mm:ss.fff'
    }
}

Describe 'Merge and window (no overlap, no gap)' {
    It 'keeps only samples after last_ts and never repeats a sample across parts' {
        $a = Join-Path $TestDrive 'a.csv'; $b = Join-Path $TestDrive 'b.csv'
        $t0 = [datetime]'2026-10-01T08:00:00'
        New-TestCsv $a $t0 20
        New-TestCsv $b $t0.AddSeconds(150) 20     # overlaps a by 5 samples
        $pa = Read-BbCsv $a; $pb = Read-BbCsv $b
        $m = Merge-BbCsv -Parts @($pa, $pb) -After $t0.AddSeconds(50)
        $m.Rows[0].Time | Should -Be $t0.AddSeconds(60)
        $m.Rows[$m.Rows.Count - 1].Time | Should -Be $t0.AddSeconds(340)
        $m.Rows.Count | Should -Be 29
        $times = $m.Rows | ForEach-Object { $_.Time }
        @($times | Select-Object -Unique).Count | Should -Be $times.Count
    }
    It 'unions columns when a later part has more counters (G3 appeared)' {
        $a = Join-Path $TestDrive 'c1.csv'; $b = Join-Path $TestDrive 'c2.csv'
        $t0 = [datetime]'2026-10-01T08:00:00'
        New-TestCsv $a $t0 3
        New-TestCsv $b $t0.AddSeconds(30) 3
        $lines = [IO.File]::ReadAllLines($b)
        $lines[0] = $lines[0] + ',"\\SYNTH01\Web Service(_Total)\Current Connections"'
        for ($i = 1; $i -lt $lines.Count; $i++) { $lines[$i] = $lines[$i] + ',"7"' }
        [IO.File]::WriteAllLines($b, $lines)
        $m = Merge-BbCsv -Parts @((Read-BbCsv $a), (Read-BbCsv $b))
        $m.Columns.Count | Should -Be 37
        $m.Rows[0].Values[36] | Should -Be ' '
        $m.Rows[5].Values[36] | Should -Be '7'
    }
}

Describe 'Validation' {
    BeforeAll {
        $script:Good = Join-Path $TestDrive 'g.csv'
        New-TestCsv $script:Good ([datetime]'2026-10-01T08:00:00') 5
    }
    It 'accepts a good CSV' {
        $m = Merge-BbCsv -Parts @(Read-BbCsv $script:Good)
        (Test-BbCsv -Merged $m -Required $script:Base36).Count | Should -Be 0
    }
    It 'rejects a bad header' {
        $m = Merge-BbCsv -Parts @(Read-BbCsv $script:Good); $m.PdhHeader = 'Time'
        $x = Test-BbCsv -Merged $m -Required $script:Base36; $x | Should -Contain 'no PDH-CSV header'
    }
    It 'rejects an empty file' {
        $m = Merge-BbCsv -Parts @(Read-BbCsv $script:Good) -After ([datetime]'2027-01-01')
        $x = Test-BbCsv -Merged $m -Required $script:Base36; $x | Should -Contain 'no rows'
    }
    It 'rejects a missing counter' {
        $m = Merge-BbCsv -Parts @(Read-BbCsv $script:Good)
        $req = @($script:Base36) + '\Memory\Not A Counter'
        $x = Test-BbCsv -Merged $m -Required $req; $x | Should -Contain 'counter missing: \Memory\Not A Counter'
    }
}

Describe 'Gaps and their causes' {
    BeforeAll {
        function Rows([int[]]$Seconds, [int[]]$Parts) {
            $t0 = [datetime]'2026-10-01T08:00:00'
            for ($i = 0; $i -lt $Seconds.Count; $i++) { [pscustomobject]@{ Time = $t0.AddSeconds($Seconds[$i]); Part = $Parts[$i] } }
        }
        $script:T0 = [datetime]'2026-10-01T08:00:00'
    }
    It 'no gap in a continuous window' {
        (Find-BbGaps -Rows @(Rows @(10, 20, 30) @(0, 0, 0)) -IntervalSeconds 10 -LastTs $script:T0).Count | Should -Be 0
    }
    It 'buffer_overrun when the first part had wrapped' {
        $g = Find-BbGaps -Rows @(Rows @(600, 610) @(0, 0)) -IntervalSeconds 10 -LastTs $script:T0 -PartInfo @([pscustomobject]@{ Reason = 'export'; Wrapped = $true })
        $g[0].cause | Should -Be 'buffer_overrun'
        $g[0].from | Should -Be '2026-10-01 08:00:00.000'
        $g[0].to | Should -Be '2026-10-01 08:10:00.000'
    }
    It 'local_cap when a dropped buffer overlaps the leading hole' {
        $d = @(@{ from = '2026-10-01 08:01:00'; to = '2026-10-01 08:09:00' })
        $g = Find-BbGaps -Rows @(Rows @(600) @(0)) -IntervalSeconds 10 -LastTs $script:T0 -PartInfo @([pscustomobject]@{ Reason = 'export'; Wrapped = $false }) -Drops $d
        $g[0].cause | Should -Be 'local_cap'
    }
    It 'machine_off between parts when the earlier one was closed by a boot, collector_restart otherwise' {
        $pi = @([pscustomobject]@{ Reason = 'boot'; Wrapped = $false }, [pscustomobject]@{ Reason = 'recreate'; Wrapped = $false }, [pscustomobject]@{ Reason = 'export'; Wrapped = $false })
        $g = Find-BbGaps -Rows @(Rows @(10, 20, 400, 410, 900) @(0, 0, 1, 1, 2)) -IntervalSeconds 10 -LastTs $script:T0 -PartInfo $pi
        $g.Count | Should -Be 2
        $g[0].cause | Should -Be 'machine_off'
        $g[1].cause | Should -Be 'collector_restart'
    }
    It 'missing_samples inside one part' {
        (Find-BbGaps -Rows @(Rows @(10, 20, 90) @(0, 0, 0)) -IntervalSeconds 10 -LastTs $script:T0)[0].cause | Should -Be 'missing_samples'
    }
}

Describe 'Blob path, template, collector compare, capacity, tasks' {
    It 'builds the blob path from the prefix and the window' {
        Get-BbBlobName -Prefix 'Sub/RG-X/VM1' -From ([datetime]'2026-10-01T22:00:00') -To ([datetime]'2026-10-02T02:00:00') |
            Should -Be 'sub/rg-x/vm1/2026/10/02/vm1_20261001-220000_20261002-020000.zip'
    }
    It 'fills the template with every counter and the parameters' {
        $c = Get-BbExpectedCounters -CollectorDir $script:Collector -PresentObjects @('Web Service')
        $c.Count | Should -Be 51
        $x = [xml]((New-BbCollectorXml -TemplatePath (Join-Path $script:Collector 'PerfmonBlackbox.template.xml') -Counters $c -MaxSizeMB 32 -SampleIntervalSeconds 5) -replace '^<\?xml[^>]*\?>', '')
        @($x.DataCollectorSet.PerformanceCounterDataCollector.Counter).Count | Should -Be 51
        $x.DataCollectorSet.SegmentMaxSize | Should -Be '32'
        $x.DataCollectorSet.PerformanceCounterDataCollector.SampleInterval | Should -Be '5'
    }
    It 'G3 auto-detect: only present objects' {
        (Get-BbExpectedCounters -CollectorDir $script:Collector -PresentObjects @()).Count | Should -Be 50
        (Get-BbExpectedCounters -CollectorDir $script:Collector -PresentObjects @('ASP.NET', 'ASP.NET Applications', '.NET CLR Memory', 'Web Service')).Count | Should -Be 56
    }
    It 'reports collector drift' {
        $exp = @('\A\b', '\C\d')
        $c = [pscustomobject]@{ Counters = @('\A\b'); SampleIntervalSeconds = 1; MaxSizeMB = 16; Circular = $true; BinaryFormat = $true; Duration = 0 }
        $r = Compare-BbCollector -Collector $c -Expected $exp -MaxSizeMB 512 -SampleIntervalSeconds 10
        $r.Count | Should -Be 3
        (Compare-BbCollector -Collector $null -Expected $exp -MaxSizeMB 512 -SampleIntervalSeconds 10)[0] | Should -Match 'does not exist'
    }
    It 'capacity: misfit reported with the numbers' {
        $cfg = @{ MaxSizeMB = 16; SampleIntervalSeconds = 1; ExportEveryHours = 24 }
        $r = Test-BbCapacity -Config $cfg -State @{ bytes_per_sample = 66600 }
        $r.Ok | Should -BeFalse
        $r.Reason | Should -Match 'buffer holds ~0.1 h at 1 s with MaxSizeMB=16'
        $r.Reason | Should -Match 'export every 24 h'
        (Test-BbCapacity -Config @{ MaxSizeMB = 512; SampleIntervalSeconds = 10; ExportEveryHours = 4 } -State @{ bytes_per_sample = 66600 }).Ok | Should -BeTrue
    }
    It 'capacity: estimated from the process count before the first export' {
        $r = Test-BbCapacity -Config @{ MaxSizeMB = 512; SampleIntervalSeconds = 10; ExportEveryHours = 4 } -State @{} -Processes 350
        $r.Estimated | Should -BeTrue
        $r.Reason | Should -Match 'estimated, 350 processes'
    }
    It 'task XML: boot and export, compared field by field' {
        $boot = New-BbTaskXml -Kind Boot -BinDir 'C:\ProgramData\PerfmonBlackbox\bin'
        $exp = New-BbTaskXml -Kind Export -BinDir 'C:\ProgramData\PerfmonBlackbox\bin' -ExportEveryHours 4
        $exp | Should -Match '<Interval>PT4H</Interval>'
        $exp | Should -Match '<StartWhenAvailable>true</StartWhenAvailable>'
        (New-BbTaskXml -Kind Export -BinDir 'x' -ExportEveryHours 24) | Should -Not -Match '<Repetition>'
        $actual = [xml]($boot -replace '^\s*<\?xml[^>]*\?>', '')
        (Compare-BbTask -Kind Boot -Actual $actual -ExpectedXml $boot).Count | Should -Be 0
        (Compare-BbTask -Kind Export -Actual $actual -ExpectedXml $exp).Count | Should -BeGreaterThan 0
        (Compare-BbTask -Kind Boot -Actual $null -ExpectedXml $boot)[0] | Should -Match 'not registered'
        # schtasks /query /xml drops <Enabled>true</Enabled> (the default): still compliant
        $noEnabled = [xml](($boot -replace '<Enabled>true</Enabled>', '') -replace '^\s*<\?xml[^>]*\?>', '')
        (Compare-BbTask -Kind Boot -Actual $noEnabled -ExpectedXml $boot).Count | Should -Be 0
    }
    It 'ACL check ignores the ACE order icacls uses' {
        Test-BbSddl 'D:PAI(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)' | Should -BeTrue
        Test-BbSddl 'D:AI(A;OICIID;FA;;;SY)(A;OICIID;FA;;;BA)' | Should -BeFalse
        Test-BbSddl 'D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;BU)' | Should -BeFalse
    }
}

Describe 'Pending buffers keep the right reason' {
    It 'a ring last written before the boot is a boot buffer, whoever restarts the collector' {
        $p = Use-TestRoot (Join-Path $TestDrive 'reason')
        $old = Join-Path $p.Blg 'PerfmonBlackbox.blg'; Set-Content $old 'x'; (Get-Item $old).LastWriteTime = (Get-Date).AddHours(-2)
        Mock Get-CimInstance { [pscustomobject]@{ LastBootUpTime = (Get-Date).AddHours(-1) } }
        $m = Move-BbBufferToPending -Reason 'start' -Paths $p
        $m[0] | Should -Match '-boot\.blg$'
        $new = Join-Path $p.Blg 'PerfmonBlackbox.blg'; Set-Content $new 'y'
        $m2 = Move-BbBufferToPending -Reason 'boot' -Paths $p
        $m2[0] | Should -Match '-start\.blg$'
        (Move-BbBufferToPending -Reason 'export' -Paths $p).Count | Should -Be 0
    }
}

Describe 'R1 check never throws (P36)' {
    BeforeEach {
        $script:Ship = Join-Path $TestDrive 'ship'; $script:Bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Force $script:Ship, $script:Bin | Out-Null
        Set-Content (Join-Path $script:Ship 'a.ps1') 'one'; Set-Content (Join-Path $script:Bin 'a.ps1') 'one'
        $script:Cfg = Join-Path $TestDrive 'config.json'; Write-BbJson $script:Cfg ([ordered]@{ MaxSizeMB = 512 })
    }
    It 'reports nothing when files and config match' {
        (Get-BbFilesDrift -Shipped @{ 'a.ps1' = (Join-Path $script:Ship 'a.ps1') } -BinDir $script:Bin -ConfigPath $script:Cfg -ExpectedConfig @{ MaxSizeMB = 512 }).Count | Should -Be 0
    }
    It 'turns an unreadable file into a reason instead of an exception' {
        Mock Get-BbSha256 { throw 'Access to the path is denied.' }
        $d = Get-BbFilesDrift -Shipped @{ 'a.ps1' = (Join-Path $script:Ship 'a.ps1') } -BinDir $script:Bin -ConfigPath $script:Cfg -ExpectedConfig @{ MaxSizeMB = 512 }
        $d[0].Id | Should -Be 'FileUnreadable'
    }
    It 'turns an unreadable config into a reason' {
        Mock Read-BbJson { throw 'Access to the path is denied.' }
        $d = Get-BbFilesDrift -Shipped @{} -BinDir $script:Bin -ConfigPath $script:Cfg -ExpectedConfig @{ MaxSizeMB = 512 }
        $d[0].Id | Should -Be 'ConfigUnreadable'
    }
    It 'reports a changed parameter' {
        $d = Get-BbFilesDrift -Shipped @{} -BinDir $script:Bin -ConfigPath $script:Cfg -ExpectedConfig @{ MaxSizeMB = 16 }
        $d[0].Phrase | Should -Be "config MaxSizeMB is '512', expected '16'"
    }
}

Describe 'Invoke-BbExport end to end on synthetic buffers' {
    BeforeEach {
        $script:Uploads.Clear()
        $script:P = Use-TestRoot (Join-Path $TestDrive ('root-' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
        $script:T0 = [datetime]'2026-10-01T08:00:00'
    }
    It 'exports two buffers as one window, then the next export starts exactly one interval later' {
        New-TestCsv (Join-Path $TestDrive 'p1.csv') $script:T0 60
        New-TestCsv (Join-Path $TestDrive 'p2.csv') $script:T0.AddSeconds(600) 60
        New-TestBlg (Join-Path $TestDrive 'p1.csv') (Join-Path $script:P.Pending '20261001-081000-00-boot.blg')
        New-TestBlg (Join-Path $TestDrive 'p2.csv') (Join-Path $script:P.Pending '20261001-082000-00-export.blg')
        $r = Invoke-BbExport -NoRoll -NoLock -Machine $script:Machine -Uploader $script:OkUploader -CollectorDir $script:Collector
        $r.Result | Should -Be 'uploaded'
        $r.Rows | Should -Be 120
        $r.Manifest.complete | Should -BeTrue
        $r.Blob | Should -Be 'synthsub/rg-synth/synth01/2026/10/01/synth01_20261001-080000_20261001-081950.zip'
        $script:Uploads.Count | Should -Be 1
        $s = Get-BbState
        $s['last_ts'] | Should -Be '2026-10-01 08:19:50.000'
        $s['seq'] | Should -Be 1
        @(Get-ChildItem $script:P.Pending).Count | Should -Be 0
        # second export: the next buffer starts one interval after the last exported sample
        New-TestCsv (Join-Path $TestDrive 'p3.csv') $script:T0.AddSeconds(1200) 30
        New-TestBlg (Join-Path $TestDrive 'p3.csv') (Join-Path $script:P.Pending '20261001-083000-00-export.blg')
        $r2 = Invoke-BbExport -NoRoll -NoLock -Machine $script:Machine -Uploader $script:OkUploader -CollectorDir $script:Collector
        $r2.Manifest.first_sample | Should -Be '2026-10-01 08:20:00.000'
        $r2.Manifest.window_from | Should -Be '2026-10-01 08:19:50.000'
        $r2.Manifest.gaps.Count | Should -Be 0
        $r2.Manifest.seq | Should -Be 2
    }
    It 'zip holds the CSV and a manifest whose hash matches' {
        New-TestCsv (Join-Path $TestDrive 'z.csv') $script:T0 40
        New-TestBlg (Join-Path $TestDrive 'z.csv') (Join-Path $script:P.Pending '20261001-081000-00-export.blg')
        $r = Invoke-BbExport -NoUpload -NoRoll -NoLock -Machine $script:Machine -CollectorDir $script:Collector
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $x = Join-Path $TestDrive 'unz'
        [IO.Compression.ZipFile]::ExtractToDirectory($r.Zip, $x)
        $man = Get-Content (Join-Path $x 'manifest.json') -Raw | ConvertFrom-Json
        (Get-BbSha256 (Join-Path $x $man.csv_name)) | Should -Be $man.csv_sha256
        $man.rows | Should -Be 40
        (Get-Content (Join-Path $x $man.csv_name) -TotalCount 1) | Should -Match '^"\(PDH-CSV 4\.0\)'
        (Get-BbState)['last_ts'] | Should -BeNullOrEmpty   # -NoUpload never commits
    }
    It 'a failed upload leaves state.json and the buffers unchanged; the next run covers both windows' {
        New-TestCsv (Join-Path $TestDrive 'f1.csv') $script:T0 30
        New-TestBlg (Join-Path $TestDrive 'f1.csv') (Join-Path $script:P.Pending '20261001-080500-00-export.blg')
        { Invoke-BbExport -NoRoll -NoLock -Machine $script:Machine -Uploader $script:FailUploader -CollectorDir $script:Collector } | Should -Throw
        (Get-BbState)['last_ts'] | Should -BeNullOrEmpty
        (Get-BbState)['last_error'] | Should -Match 'storage unreachable'
        @(Get-ChildItem $script:P.Pending).Count | Should -Be 1
        New-TestCsv (Join-Path $TestDrive 'f2.csv') $script:T0.AddSeconds(300) 30
        New-TestBlg (Join-Path $TestDrive 'f2.csv') (Join-Path $script:P.Pending '20261001-081000-00-export.blg')
        $r = Invoke-BbExport -NoRoll -NoLock -Machine $script:Machine -Uploader $script:OkUploader -CollectorDir $script:Collector
        $r.Rows | Should -Be 60
        $r.Manifest.complete | Should -BeTrue
    }
    It 'reports a buffer_overrun gap (complete: false) when the ring wrapped past last_ts' {
        $s = Get-BbState; $s['last_ts'] = '2026-10-01 07:00:00.000'; Write-BbJson $script:P.State $s
        $cfg = Get-BbConfig; $cfg['MaxSizeMB'] = 16; Write-BbJson $script:P.Config $cfg
        New-TestCsv (Join-Path $TestDrive 'o.csv') $script:T0 30
        $blg = Join-Path $script:P.Pending '20261001-081000-00-export.blg'
        New-TestBlg (Join-Path $TestDrive 'o.csv') $blg
        # pretend the ring had filled (size >= 95 % of MaxSizeMB) by padding the file
        $fs = [IO.File]::OpenWrite($blg); $fs.SetLength(16MB); $fs.Close()
        Mock Invoke-BbTool -ParameterFilter { $FilePath -eq 'relog.exe' -and $ArgumentList -contains 'csv' } {
            Copy-Item (Join-Path $TestDrive 'o.csv') $ArgumentList[4]; [pscustomobject]@{ ExitCode = 0; Output = @() } }
        $r = Invoke-BbExport -NoRoll -NoLock -Machine $script:Machine -Uploader $script:OkUploader -CollectorDir $script:Collector
        $r.Manifest.complete | Should -BeFalse
        $r.Manifest.gaps[0].cause | Should -Be 'buffer_overrun'
        $r.Manifest.gaps[0].from | Should -Be '2026-10-01 07:00:00.000'
        $r.Manifest.gaps[0].to | Should -Be '2026-10-01 08:00:00.000'
        $script:Uploads[0].meta.complete | Should -Be 'false'
        Should -Invoke Write-BbEvent -ParameterFilter { $EntryType -eq 'Warning' }
    }
}
