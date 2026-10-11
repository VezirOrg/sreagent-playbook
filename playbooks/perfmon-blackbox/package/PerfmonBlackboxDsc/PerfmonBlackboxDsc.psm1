<#
PerfmonBlackboxDsc: class-based DSC resources R1-R6 of the PerfmonBlackbox Machine Configuration package (design sec. 2).

Run by the Machine Configuration agent in its own PowerShell 7 (P25). Windows modules are not loadable there, so
everything goes through logman.exe, schtasks.exe, icacls.exe, relog.exe and .NET (PerfmonBlackbox.Common.ps1),
in Windows PowerShell 5.1 syntax. Each resource has a real Test, and Get returns Reasons (Code/Phrase), so the
guest assignment shows drift per item. The six policy parameters reach R1 only (P23); R1 writes config.json and
R2-R6 read it.
#>

. (Join-Path $PSScriptRoot 'Files\PerfmonBlackbox.Common.ps1')

$script:BbFilesDir = Join-Path $PSScriptRoot 'Files'

function New-BbReason {
    param([string]$Resource, [string]$Id, [string]$Phrase)
    $r = [Reason]::new()
    $r.Code = "$Resource`:$Resource`:$Id"
    $r.Phrase = $Phrase
    return $r
}

function Get-BbBinDir { return (Get-BbPaths).Bin }

function Get-BbShippedFiles {
    # relative path -> full path of every file the package ships (scripts at bin\, collector files at bin\collector\)
    $out = @{}
    foreach ($f in Get-ChildItem -LiteralPath $script:BbFilesDir -File -Recurse) {
        $rel = $f.FullName.Substring($script:BbFilesDir.Length).TrimStart('\')
        $out[$rel] = $f.FullName
    }
    return $out
}

function Get-BbExpectedConfig {
    param($Res)
    [ordered]@{
        MaxSizeMB                = [int]$Res.MaxSizeMB
        SampleIntervalSeconds    = [int]$Res.SampleIntervalSeconds
        ExportEveryHours         = [int]$Res.ExportEveryHours
        StorageAccountResourceId = [string]$Res.StorageAccountResourceId
        ContainerName            = [string]$Res.ContainerName
        LocalKeepMB              = [int]$Res.LocalKeepMB
    }
}

function Test-BbParameters {
    param($Res)
    $r = @()
    $c = Get-BbExpectedConfig $Res
    if ($c.MaxSizeMB -lt 16 -or $c.MaxSizeMB -gt 8192) { $r += "MaxSizeMB $($c.MaxSizeMB) is outside 16..8192" }
    if ($c.SampleIntervalSeconds -lt 1 -or $c.SampleIntervalSeconds -gt 300) { $r += "SampleIntervalSeconds $($c.SampleIntervalSeconds) is outside 1..300" }
    if (@(1, 2, 3, 4, 6, 8, 12, 24) -notcontains $c.ExportEveryHours) { $r += "ExportEveryHours $($c.ExportEveryHours) must divide 24 (1, 2, 3, 4, 6, 8, 12, 24)" }
    if ($c.StorageAccountResourceId -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Storage/storageAccounts/[a-z0-9]{3,24}$') { $r += 'StorageAccountResourceId is not a storage account resource ID' }
    if ($c.ContainerName -notmatch '^[a-z0-9](?!.*--)[a-z0-9-]{1,61}[a-z0-9]$') { $r += "ContainerName '$($c.ContainerName)' is not a valid container name" }
    if ($c.LocalKeepMB -lt $c.MaxSizeMB) { $r += "LocalKeepMB $($c.LocalKeepMB) is smaller than MaxSizeMB $($c.MaxSizeMB)" }
    return , $r
}

class Reason {
    [DscProperty()]
    [string] $Code

    [DscProperty()]
    [string] $Phrase
}

# R1: files, config.json and the folder ACL
[DscResource()]
class BlackboxFiles {
    [DscProperty(Key)] [string] $Name
    [DscProperty()] [string] $MaxSizeMB = '512'
    [DscProperty()] [string] $SampleIntervalSeconds = '10'
    [DscProperty()] [string] $ExportEveryHours = '4'
    [DscProperty()] [string] $StorageAccountResourceId
    [DscProperty()] [string] $ContainerName = 'perfmon'
    [DscProperty()] [string] $LocalKeepMB = '1024'
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [Reason[]] Check() {
        $out = @()
        foreach ($t in (Test-BbParameters $this)) { $out += New-BbReason 'BlackboxFiles' 'BadParameter' $t }
        $p = Get-BbPaths
        $bin = $p.Bin
        $files = Get-BbShippedFiles
        foreach ($rel in $files.Keys) {
            $dst = Join-Path $bin $rel
            if (-not (Test-Path -LiteralPath $dst)) { $out += New-BbReason 'BlackboxFiles' 'FileMissing' "file $rel is missing"; continue }
            if ((Get-BbSha256 $dst) -ne (Get-BbSha256 $files[$rel])) { $out += New-BbReason 'BlackboxFiles' 'FileDiffers' "file $rel differs from the package" }
        }
        $cfg = Read-BbJson $p.Config
        $exp = Get-BbExpectedConfig $this
        if (-not $cfg) { $out += New-BbReason 'BlackboxFiles' 'NoConfig' 'config.json is missing' }
        else {
            foreach ($k in $exp.Keys) {
                if ("$($cfg[$k])" -ne "$($exp[$k])") { $out += New-BbReason 'BlackboxFiles' 'ConfigDiffers' "config $k is '$($cfg[$k])', expected '$($exp[$k])'" }
            }
        }
        if (Test-Path -LiteralPath $p.Root) {
            $sddl = Get-BbAclSddl $p.Root
            if ($sddl -ne $script:BbSddl) { $out += New-BbReason 'BlackboxFiles' 'AclDiffers' "folder ACL is '$sddl', expected SYSTEM and Administrators only" }
        }
        return $out
    }

    [BlackboxFiles] Get() {
        $this.Reasons = $this.Check()
        return $this
    }

    [bool] Test() { return (@($this.Check()).Count -eq 0) }

    [void] Set() {
        $bad = Test-BbParameters $this
        if ($bad.Count) { throw "invalid parameters: $($bad -join '; ')" }
        $p = Get-BbPaths
        foreach ($d in $p.Root, $p.Bin, $p.Blg, $p.Pending, $p.Work, $p.Outbox, $p.Log) { $null = New-Item -ItemType Directory -Force -Path $d }
        Set-BbAcl $p.Root
        $files = Get-BbShippedFiles
        foreach ($rel in $files.Keys) {
            $dst = Join-Path $p.Bin $rel
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst)
            Copy-Item -LiteralPath $files[$rel] -Destination $dst -Force
        }
        Write-BbJson $p.Config (Get-BbExpectedConfig $this)
    }
}

# R2: the Data Collector Set equals the counter list (36 + G1 + G2 + present G3), interval, size, circular, binary
[DscResource()]
class BlackboxCollector {
    [DscProperty(Key)] [string] $Name
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [Reason[]] Check() {
        $out = @()
        try { $cfg = Get-BbConfig } catch { return @(New-BbReason 'BlackboxCollector' 'NoConfig' 'config.json is missing (BlackboxFiles)') }
        $exp = Get-BbExpectedCounters -CollectorDir (Join-Path (Get-BbBinDir) 'collector')
        foreach ($t in (Compare-BbCollector -Collector (Get-BbCollector) -Expected $exp -MaxSizeMB $cfg['MaxSizeMB'] -SampleIntervalSeconds $cfg['SampleIntervalSeconds'])) {
            $out += New-BbReason 'BlackboxCollector' 'CollectorDiffers' $t
        }
        return $out
    }

    [BlackboxCollector] Get() { $this.Reasons = $this.Check(); return $this }

    [bool] Test() { return (@($this.Check()).Count -eq 0) }

    [void] Set() {
        $lock = Lock-Bb
        try {
            $n = Install-BbCollector -Config (Get-BbConfig) -BinDir (Get-BbBinDir)
            Write-BbLog "collector (re)created with $n counters"
        } finally { Unlock-Bb $lock }
    }
}

# R3: the collector is running
[DscResource()]
class BlackboxRunning {
    [DscProperty(Key)] [string] $Name
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [Reason[]] Check() {
        $c = Get-BbCollector
        if (-not $c) { return @(New-BbReason 'BlackboxRunning' 'NoCollector' 'collector set PerfmonBlackbox does not exist') }
        if ($c.Status -ne 'Running') { return @(New-BbReason 'BlackboxRunning' 'NotRunning' "collector status is $($c.Status)") }
        return @()
    }

    [BlackboxRunning] Get() { $this.Reasons = $this.Check(); return $this }

    [bool] Test() { return (@($this.Check()).Count -eq 0) }

    [void] Set() {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $script = Join-Path (Get-BbBinDir) 'Start-PerfmonBlackbox.ps1'
        $r = Invoke-BbTool $ps @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Reason', 'start')
        if ($r.ExitCode -ne 0) { throw "Start-PerfmonBlackbox.ps1 failed ($($r.ExitCode))" }
    }
}

# R4: \PerfmonBlackbox\Boot (at startup, SYSTEM, highest)
[DscResource()]
class BlackboxBootTask {
    [DscProperty(Key)] [string] $Name
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [string] Expected() { return (New-BbTaskXml -Kind 'Boot' -BinDir (Get-BbBinDir)) }

    [Reason[]] Check() {
        $out = @()
        foreach ($t in (Compare-BbTask -Kind 'Boot' -Actual (Get-BbTask 'Boot') -ExpectedXml $this.Expected())) { $out += New-BbReason 'BlackboxBootTask' 'TaskDiffers' $t }
        return $out
    }

    [BlackboxBootTask] Get() { $this.Reasons = $this.Check(); return $this }

    [bool] Test() { return (@($this.Check()).Count -eq 0) }

    [void] Set() { Register-BbTask -Kind 'Boot' -Xml $this.Expected() }
}

# R5: \PerfmonBlackbox\Export (daily, every ExportEveryHours, SYSTEM, StartWhenAvailable)
[DscResource()]
class BlackboxExportTask {
    [DscProperty(Key)] [string] $Name
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [string] Expected() {
        $h = 4
        try { $h = (Get-BbConfig)['ExportEveryHours'] } catch { }
        return (New-BbTaskXml -Kind 'Export' -BinDir (Get-BbBinDir) -ExportEveryHours $h)
    }

    [Reason[]] Check() {
        $out = @()
        foreach ($t in (Compare-BbTask -Kind 'Export' -Actual (Get-BbTask 'Export') -ExpectedXml $this.Expected())) { $out += New-BbReason 'BlackboxExportTask' 'TaskDiffers' $t }
        return $out
    }

    [BlackboxExportTask] Get() { $this.Reasons = $this.Check(); return $this }

    [bool] Test() { return (@($this.Check()).Count -eq 0) }

    [void] Set() { Register-BbTask -Kind 'Export' -Xml $this.Expected() }
}

# R6: capacity check, audit only (CHOICE 9): buffer hours >= 1.5 x the export window, numbers in the reason
[DscResource()]
class BlackboxCapacity {
    [DscProperty(Key)] [string] $Name
    [DscProperty(NotConfigurable)] [Reason[]] $Reasons

    [hashtable] Result() {
        try { $cfg = Get-BbConfig } catch { return @{ Ok = $false; Reason = 'config.json is missing (BlackboxFiles)' } }
        return (Test-BbCapacity -Config $cfg -State (Get-BbState))
    }

    [BlackboxCapacity] Get() {
        $r = $this.Result()
        if ($r.Ok) { $this.Reasons = @(New-BbReason 'BlackboxCapacity' 'CapacityOk' $r.Reason) }
        else { $this.Reasons = @(New-BbReason 'BlackboxCapacity' 'BufferTooSmall' $r.Reason) }
        return $this
    }

    [bool] Test() { return [bool]$this.Result().Ok }

    [void] Set() { }  # audit only: a misfit is reported, never "fixed" behind the adopter's back
}
