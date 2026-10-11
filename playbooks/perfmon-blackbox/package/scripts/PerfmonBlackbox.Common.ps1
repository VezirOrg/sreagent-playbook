<#
PerfmonBlackbox.Common.ps1: shared functions of the PerfmonBlackbox recorder (design sec. 2, decisions P20-P26).

Dot-sourced by Start-PerfmonBlackbox.ps1, Export-PerfmonBlackbox.ps1 (Windows PowerShell 5.1, scheduled tasks as
SYSTEM) and by the DSC resources (the Machine Configuration agent's own PowerShell 7). Windows PowerShell 5.1
syntax and cmdlets only (P25); external tools are logman.exe, relog.exe, schtasks.exe and icacls.exe, which ship
with Windows Server. Nothing here holds a secret; tokens live in memory only.
#>

$script:BbRoot = Join-Path $env:ProgramData 'PerfmonBlackbox'
$script:BbSetName = 'PerfmonBlackbox'
$script:BbEventSource = 'PerfmonBlackbox'
$script:BbG3Objects = @('ASP.NET', 'ASP.NET Applications', '.NET CLR Memory', 'Web Service')

function Get-BbPaths {
    param([string]$Root = $script:BbRoot)
    [pscustomobject]@{
        Root     = $Root
        Bin      = Join-Path $Root 'bin'
        Blg      = Join-Path $Root 'blg'
        Pending  = Join-Path $Root 'pending'
        Work     = Join-Path $Root 'work'
        Outbox   = Join-Path $Root 'outbox'
        Log      = Join-Path $Root 'log'
        Config   = Join-Path $Root 'config.json'
        State    = Join-Path $Root 'state.json'
        Lock     = Join-Path $Root 'export.lock'
    }
}

# ---------- config and state ----------

function ConvertTo-BbHashtable {
    # ConvertFrom-Json gives PSCustomObject in 5.1 (-AsHashtable is 7-only): turn it into nested hashtables
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-BbHashtable $p.Value }
        return $h
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $a = @()
        foreach ($i in $InputObject) { $a += , (ConvertTo-BbHashtable $i) }
        return , $a
    }
    return $InputObject
}

function Read-BbJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path)
    if (-not $text.Trim()) { return $null }
    return ConvertTo-BbHashtable ($text | ConvertFrom-Json)
}

function Write-BbJson {
    # write to a temp file, then replace: a crash never leaves half a state file
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Object)
    $tmp = "$Path.tmp"
    $json = $Object | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-BbConfig {
    param([string]$Path = (Get-BbPaths).Config)
    $c = Read-BbJson $Path
    if (-not $c) { throw "no config at $Path (the DSC resource BlackboxFiles writes it)" }
    foreach ($k in 'MaxSizeMB', 'SampleIntervalSeconds', 'ExportEveryHours', 'LocalKeepMB') { $c[$k] = [int]$c[$k] }
    return $c
}

function Get-BbState {
    param([string]$Path = (Get-BbPaths).State)
    $s = Read-BbJson $Path
    if (-not $s) { $s = @{} }
    foreach ($k in 'last_ts', 'seq', 'buffer_hours', 'bytes_per_sample', 'local_cap_drops', 'last_error', 'last_export_utc') {
        if (-not $s.ContainsKey($k)) { $s[$k] = $null }
    }
    if ($null -eq $s['seq']) { $s['seq'] = 0 }
    if ($null -eq $s['local_cap_drops']) { $s['local_cap_drops'] = @() }
    return $s
}

# ---------- counters, template, collector ----------

function Read-BbCounterFile {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ -and $_.Trim() -and -not $_.StartsWith('#') } |
        ForEach-Object { $_.Trim() }
}

function Get-BbCounterObject {
    # '\Process(*)\Private Bytes' -> 'Process'; '\Memory\Available MBytes' -> 'Memory'
    param([Parameter(Mandatory)][string]$Counter)
    $p = $Counter.TrimStart('\').Split('\')[0]
    $i = $p.IndexOf('(')
    if ($i -ge 0) { return $p.Substring(0, $i) }
    return $p
}

function Test-BbCounterObject {
    # does a performance counter object (category) exist on this machine? (G3 auto-detect, CHOICE 10)
    param([Parameter(Mandatory)][string]$Object)
    try {
        return [System.Diagnostics.PerformanceCounterCategory]::Exists($Object)
    } catch {
        $null = & typeperf.exe -q "$Object" 2>&1
        return ($LASTEXITCODE -eq 0)
    }
}

function Get-BbExpectedCounters {
    # 36 + G1 + G2, plus each G3 line whose object exists now (or as told by -PresentObjects, for tests)
    param([Parameter(Mandatory)][string]$CollectorDir, [string[]]$PresentObjects)
    $list = @()
    $list += Read-BbCounterFile (Join-Path $CollectorDir 'PerfmonBlackbox.counters.txt')
    $list += Read-BbCounterFile (Join-Path $CollectorDir 'PerfmonBlackbox.counters-g1-system.txt')
    $list += Read-BbCounterFile (Join-Path $CollectorDir 'PerfmonBlackbox.counters-g2-process.txt')
    foreach ($c in (Read-BbCounterFile (Join-Path $CollectorDir 'PerfmonBlackbox.counters-g3-web.txt'))) {
        $o = Get-BbCounterObject $c
        if ($PSBoundParameters.ContainsKey('PresentObjects')) { $ok = $PresentObjects -contains $o } else { $ok = Test-BbCounterObject $o }
        if ($ok) { $list += $c }
    }
    return , $list
}

function New-BbCollectorXml {
    # fill the sanitized template (P11) with the parameters and the full counter list
    param([Parameter(Mandatory)][string]$TemplatePath, [Parameter(Mandatory)][string[]]$Counters,
          [Parameter(Mandatory)][int]$MaxSizeMB, [Parameter(Mandatory)][int]$SampleIntervalSeconds)
    $xml = [System.IO.File]::ReadAllText($TemplatePath)
    $xml = $xml.Replace('{{MaxSizeMB}}', "$MaxSizeMB").Replace('{{SampleIntervalSeconds}}', "$SampleIntervalSeconds")
    $xml = [regex]::Replace($xml, '[ \t]*<Counter>.*?</Counter>\r?\n', '')
    $lines = ($Counters | ForEach-Object { "`t`t<Counter>$([System.Security.SecurityElement]::Escape($_))</Counter>`r`n" }) -join ''
    $xml = $xml.Replace("`t</PerformanceCounterDataCollector>", "$lines`t</PerformanceCounterDataCollector>")
    if ($xml -match '\{\{\w+\}\}') { throw 'unfilled placeholder in the collector template' }
    return $xml.Replace('encoding="UTF-8"', 'encoding="UTF-16"')
}

function Get-BbCollector {
    # the Data Collector Set as PLA sees it, or $null
    param([string]$Name = $script:BbSetName)
    $pla = New-Object -ComObject Pla.DataCollectorSet
    try { $pla.Query($Name, $null) } catch { return $null }
    $dc = $pla.DataCollectors.Item(0)
    $status = switch ([int]$pla.Status) { 0 { 'Stopped' } 1 { 'Running' } 2 { 'Compiling' } 3 { 'Pending' } default { 'Unknown' } }
    [pscustomobject]@{
        Name                  = $Name
        Status                = $status
        Counters              = @($dc.PerformanceCounters)
        SampleIntervalSeconds = [int]$dc.SampleInterval
        MaxSizeMB             = [int]$pla.SegmentMaxSize
        Circular              = [bool]$dc.LogCircular
        BinaryFormat          = ([int]$dc.LogFileFormat -eq 3)
        Duration              = [int]$pla.Duration
        RootPath              = [string]$pla.RootPath
    }
}

function Compare-BbCollector {
    # reasons why the collector differs from what it should be (empty = compliant)
    param($Collector, [Parameter(Mandatory)][string[]]$Expected, [Parameter(Mandatory)][int]$MaxSizeMB,
          [Parameter(Mandatory)][int]$SampleIntervalSeconds)
    $r = @()
    if (-not $Collector) { return , @('collector set PerfmonBlackbox does not exist') }
    $missing = @($Expected | Where-Object { $Collector.Counters -notcontains $_ })
    $extra = @($Collector.Counters | Where-Object { $Expected -notcontains $_ })
    if ($missing.Count -or $extra.Count) {
        $r += "counter list differs: $($missing.Count) missing, $($extra.Count) extra (expected $($Expected.Count))"
    }
    if ($Collector.SampleIntervalSeconds -ne $SampleIntervalSeconds) { $r += "interval $($Collector.SampleIntervalSeconds) s, expected $SampleIntervalSeconds s" }
    if ($Collector.MaxSizeMB -ne $MaxSizeMB) { $r += "max size $($Collector.MaxSizeMB) MB, expected $MaxSizeMB MB" }
    if (-not $Collector.Circular) { $r += 'not circular' }
    if (-not $Collector.BinaryFormat) { $r += 'not a binary log' }
    if ($Collector.Duration -ne 0) { $r += "duration limit $($Collector.Duration) s, expected none" }
    return , $r
}

function Invoke-BbTool {
    # run an exe, return exit code and output lines (stderr merged)
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @())
    $out = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($out) }
}

function Get-BbBlgInfo {
    # samples, first and last sample of a CLOSED .blg (relog -q); a running circular file cannot be read (lab18)
    param([Parameter(Mandatory)][string]$Path)
    $r = Invoke-BbTool relog.exe @($Path, '-q')
    $info = [ordered]@{ Path = $Path; Bytes = (Get-Item -LiteralPath $Path).Length; Samples = 0; Begin = $null; End = $null; Readable = ($r.ExitCode -eq 0) }
    foreach ($l in $r.Output) {
        if ($l -match '^\s*Samples:\s*(\d+)') { $info.Samples = [int]$Matches[1] }
        elseif ($l -match '^\s*Begin:\s*(.+)$') { $info.Begin = $Matches[1].Trim() }
        elseif ($l -match '^\s*End:\s*(.+)$') { $info.End = $Matches[1].Trim() }
    }
    [pscustomobject]$info
}

function Move-BbBufferToPending {
    # keep the current (stopped) ring as a pending buffer before any (re)start: a circular log restarted with
    # overwrite would wipe it (design sec. 2.2 step 0). Reason: export | boot | recreate | start.
    param([Parameter(Mandatory)][string]$Reason, $Paths = (Get-BbPaths), [datetime]$Now = (Get-Date))
    $moved = @()
    $files = @(Get-ChildItem -LiteralPath $Paths.Blg -Filter *.blg -ErrorAction SilentlyContinue)
    if ($files.Count) { $null = New-Item -ItemType Directory -Force -Path $Paths.Pending }
    $n = 0
    foreach ($f in ($files | Sort-Object LastWriteTime)) {
        if ($f.Length -le 0) { Remove-Item -LiteralPath $f.FullName -Force; continue }
        $name = '{0}-{1:D2}-{2}.blg' -f $Now.ToString('yyyyMMdd-HHmmss'), $n, $Reason
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $Paths.Pending $name)
        $moved += $name
        $n++
    }
    return , $moved
}

function Get-BbPendingReason {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -match '^\d{8}-\d{6}-\d{2}-(\w+)\.blg$') { return $Matches[1] }
    return 'unknown'
}

# ---------- PDH CSV: read, merge, filter, validate ----------

function Split-BbCsvLine {
    # PDH-CSV rows are fully quoted: "a","b",... (instance names may hold commas, never quotes)
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    $t = $Line.Trim()
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    return , ($t -split '","')
}

function Join-BbCsvLine {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Fields)
    return '"' + ($Fields -join '","') + '"'
}

function Get-BbTimeFormat {
    # month/day or day/month: a first field > 12 means day first; ambiguous -> the machine's culture
    param([string[]]$Stamps)
    foreach ($s in $Stamps) {
        $p = $s.Split('/')
        if ($p.Count -ge 3) {
            if ([int]$p[0] -gt 12) { return 'dd/MM/yyyy HH:mm:ss.fff' }
            if ([int]$p[1] -gt 12) { return 'MM/dd/yyyy HH:mm:ss.fff' }
        }
    }
    if ([System.Globalization.CultureInfo]::CurrentCulture.DateTimeFormat.ShortDatePattern.StartsWith('d')) { return 'dd/MM/yyyy HH:mm:ss.fff' }
    return 'MM/dd/yyyy HH:mm:ss.fff'
}

function ConvertFrom-BbStamp {
    param([Parameter(Mandatory)][string]$Stamp, [Parameter(Mandatory)][string]$Format)
    $s = $Stamp.Trim()
    if ($s -notmatch '\.\d{3}$') { $s = "$s.000" }
    return [datetime]::ParseExact($s, $Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Read-BbCsv {
    # one relog CSV -> header fields and rows (each: Time, Fields[]), timestamps parsed
    param([Parameter(Mandatory)][string]$Path, [string]$Format)
    $lines = [System.IO.File]::ReadAllLines($Path)
    if (-not $lines.Count) { throw "empty CSV: $Path" }
    $header = Split-BbCsvLine $lines[0]
    $raw = @()
    for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim()) { $raw += , (Split-BbCsvLine $lines[$i]) } }
    if (-not $Format) { $Format = Get-BbTimeFormat ($raw | Select-Object -First 500 | ForEach-Object { $_[0] }) }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($f in $raw) { $rows.Add([pscustomobject]@{ Time = (ConvertFrom-BbStamp $f[0] $Format); Fields = $f }) }
    [pscustomobject]@{ Header = $header; Rows = $rows; Format = $Format; Path = $Path }
}

function Merge-BbCsv {
    # pending CSVs in time order -> one header (union of columns, first file's order first) and rows strictly
    # after -After (no overlap with the last export) and strictly increasing (parts never repeat a sample).
    # Each row remembers the part it came from (for gap causes).
    param([Parameter(Mandatory)][object[]]$Parts, $After)
    $cols = New-Object System.Collections.Generic.List[string]
    $index = @{}
    foreach ($p in $Parts) {
        for ($i = 1; $i -lt $p.Header.Count; $i++) {
            $c = $p.Header[$i]
            if (-not $index.ContainsKey($c)) { $index[$c] = $cols.Count; $cols.Add($c) }
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    $last = $After
    $k = 0
    foreach ($p in $Parts) {
        $map = @()
        for ($i = 1; $i -lt $p.Header.Count; $i++) { $map += $index[$p.Header[$i]] }
        foreach ($r in $p.Rows) {
            if ($null -ne $last -and $r.Time -le $last) { continue }
            $vals = New-Object string[] $cols.Count
            for ($i = 0; $i -lt $map.Count; $i++) {
                if ($i + 1 -lt $r.Fields.Count) { $vals[$map[$i]] = $r.Fields[$i + 1] } else { $vals[$map[$i]] = ' ' }
            }
            for ($j = 0; $j -lt $vals.Count; $j++) { if ($null -eq $vals[$j]) { $vals[$j] = ' ' } }
            $rows.Add([pscustomobject]@{ Time = $r.Time; Stamp = $r.Fields[0]; Values = $vals; Part = $k })
            $last = $r.Time
        }
        $k++
    }
    [pscustomobject]@{ PdhHeader = $Parts[0].Header[0]; Columns = $cols; Rows = $rows }
}

function Write-BbCsv {
    param([Parameter(Mandatory)]$Merged, [Parameter(Mandatory)][string]$Path)
    $w = New-Object System.IO.StreamWriter($Path, $false, (New-Object System.Text.UTF8Encoding $false))
    try {
        $w.Write((Join-BbCsvLine (@($Merged.PdhHeader) + @($Merged.Columns))) + "`r`n")
        foreach ($r in $Merged.Rows) { $w.Write((Join-BbCsvLine (@($r.Stamp) + @($r.Values))) + "`r`n") }
    } finally { $w.Close() }
}

function Test-BbCsv {
    # design sec. 2.2 step 4: PDH header, >= 1 row, every counter of the base list present (a wildcard counter as at
    # least one instance), first/last sample inside the window. Returns reasons (empty = valid).
    param([Parameter(Mandatory)]$Merged, [Parameter(Mandatory)][string[]]$Required, $WindowFrom, $WindowTo)
    $r = @()
    if ($Merged.PdhHeader -notmatch '^\(PDH-CSV 4\.0\)') { $r += 'no PDH-CSV header' }
    if (-not $Merged.Rows.Count) { $r += 'no rows' ; return , $r }
    $paths = @($Merged.Columns | ForEach-Object { $_ -replace '^\\\\[^\\]+', '' })
    foreach ($c in $Required) {
        $pat = '^' + [regex]::Escape($c).Replace('\(\*\)', '\([^\\]*\)') + '$'
        if (-not ($paths | Where-Object { $_ -match $pat } | Select-Object -First 1)) { $r += "counter missing: $c" }
    }
    if ($null -ne $WindowFrom -and $Merged.Rows[0].Time -le $WindowFrom) { $r += 'first sample not after the last export' }
    if ($null -ne $WindowTo -and $Merged.Rows[$Merged.Rows.Count - 1].Time -gt $WindowTo) { $r += 'last sample after the window end' }
    return , $r
}

function Find-BbGaps {
    # holes in the exported window (design sec. 2.2 step 3). Rows carry .Part (index into $PartInfo, each with
    # .Reason = why that pending buffer was closed: export|boot|recreate|start, and .Wrapped = the ring had filled).
    # A hole is a step > 2 x interval. Causes:
    #   leading hole (from LastTs): buffer_overrun if the first part had wrapped, local_cap if a dropped buffer
    #     overlaps it, else collector_restart
    #   hole between two parts: machine_off if the earlier part was closed by a boot, else collector_restart
    #   hole inside one part: missing_samples
    param([Parameter(Mandatory)]$Rows, [Parameter(Mandatory)][int]$IntervalSeconds, $LastTs, [object[]]$PartInfo = @(),
          [object[]]$Drops = @())
    $gaps = @()
    $limit = 2 * $IntervalSeconds
    if (-not $Rows.Count) { return , $gaps }
    if ($null -ne $LastTs) {
        $first = $Rows[0].Time
        $sec = ($first - $LastTs).TotalSeconds
        if ($sec -gt $limit) {
            $cause = 'collector_restart'
            $p0 = $null
            if ($PartInfo.Count -gt $Rows[0].Part) { $p0 = $PartInfo[$Rows[0].Part] }
            if ($p0 -and $p0.Wrapped) { $cause = 'buffer_overrun' }
            else {
                foreach ($d in $Drops) {
                    if ([datetime]$d.from -lt $first -and [datetime]$d.to -gt $LastTs) { $cause = 'local_cap' }
                }
            }
            $gaps += [ordered]@{ from = $LastTs.ToString('yyyy-MM-dd HH:mm:ss.fff'); to = $first.ToString('yyyy-MM-dd HH:mm:ss.fff'); seconds = [math]::Round($sec, 3); cause = $cause }
        }
    }
    for ($i = 1; $i -lt $Rows.Count; $i++) {
        $a = $Rows[$i - 1]; $b = $Rows[$i]
        $sec = ($b.Time - $a.Time).TotalSeconds
        if ($sec -le $limit) { continue }
        if ($a.Part -ne $b.Part) {
            $cause = 'collector_restart'
            if ($PartInfo.Count -gt $a.Part -and $PartInfo[$a.Part].Reason -eq 'boot') { $cause = 'machine_off' }
        } else { $cause = 'missing_samples' }
        $gaps += [ordered]@{ from = $a.Time.ToString('yyyy-MM-dd HH:mm:ss.fff'); to = $b.Time.ToString('yyyy-MM-dd HH:mm:ss.fff'); seconds = [math]::Round($sec, 3); cause = $cause }
    }
    return , $gaps
}

# ---------- capacity (R6, design sec. 2.6) ----------

function Get-BbEstimatedBytesPerSample {
    # P16 formula from lab18 + the real captures (decisions P27): ~45-54 bytes per value; 10 values per process
    # + about 100 machine-wide values for the full set
    param([Parameter(Mandatory)][int]$Processes)
    return [int](4500 + 530 * $Processes)
}

function Get-BbBufferHours {
    param([Parameter(Mandatory)][double]$BytesPerSample, [Parameter(Mandatory)][int]$MaxSizeMB, [Parameter(Mandatory)][int]$SampleIntervalSeconds)
    if ($BytesPerSample -le 0) { return $null }
    return [math]::Round(($MaxSizeMB * 1MB / $BytesPerSample) * $SampleIntervalSeconds / 3600, 1)
}

function Test-BbCapacity {
    # R6: buffer hours >= 1.5 x the export window. Returns @{ Ok; Reason; BufferHours; Estimated }
    param([Parameter(Mandatory)]$Config, $State, [int]$Processes = 0)
    $bps = $null; $est = $false
    if ($State -and $State['bytes_per_sample']) { $bps = [double]$State['bytes_per_sample'] }
    else {
        if (-not $Processes) { $Processes = @(Get-Process).Count }
        $bps = Get-BbEstimatedBytesPerSample $Processes
        $est = $true
    }
    $hours = Get-BbBufferHours $bps $Config['MaxSizeMB'] $Config['SampleIntervalSeconds']
    $need = 1.5 * $Config['ExportEveryHours']
    $kind = 'measured'
    if ($est) { $kind = "estimated, $Processes processes" }
    $txt = "buffer holds ~$hours h at $($Config['SampleIntervalSeconds']) s with MaxSizeMB=$($Config['MaxSizeMB']) ($kind, $([int]$bps) bytes/sample), export every $($Config['ExportEveryHours']) h"
    if ($hours -ge $need) {
        return @{ Ok = $true; Reason = "$txt; margin ok (>= 1.5 x)"; BufferHours = $hours; Estimated = $est }
    }
    return @{ Ok = $false; BufferHours = $hours; Estimated = $est
        Reason = "$txt`: less than 1.5 x the export window, data will be lost; raise MaxSizeMB, lengthen the interval or export more often" }
}

# ---------- identity, metadata, blob path ----------

function Get-BbIdentityKind {
    # Arc: the Connected Machine agent sets IDENTITY_ENDPOINT machine-wide (HIMDS, localhost:40342); else IMDS
    $ep = [Environment]::GetEnvironmentVariable('IDENTITY_ENDPOINT', 'Machine')
    if (-not $ep) { $ep = $env:IDENTITY_ENDPOINT }
    if ($ep -and $ep -match 'localhost:40342|127\.0\.0\.1:40342') { return 'himds' }
    return 'imds'
}

function Invoke-BbHimds {
    # HIMDS challenge flow: the first call returns 401 with a key-file path; SYSTEM reads it and repeats the call
    # with Basic auth. The key and the token stay in memory.
    param([Parameter(Mandatory)][string]$Uri)
    try {
        $null = Invoke-WebRequest -Uri $Uri -Headers @{ Metadata = 'true' } -UseBasicParsing -TimeoutSec 20
        throw 'HIMDS did not ask for the challenge'
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp -or [int]$resp.StatusCode -ne 401) { throw }
        $h = $resp.Headers['WWW-Authenticate']
        if ($h -notmatch 'Basic realm=(.+)$') { throw 'HIMDS challenge without a key file' }
        $keyPath = $Matches[1].Trim()
        $key = [System.IO.File]::ReadAllText($keyPath)
        $r = Invoke-WebRequest -Uri $Uri -Headers @{ Metadata = 'true'; Authorization = "Basic $key" } -UseBasicParsing -TimeoutSec 20
        return $r.Content
    }
}

function Get-BbToken {
    param([string]$Resource = 'https://storage.azure.com/')
    $kind = Get-BbIdentityKind
    $q = 'resource=' + [uri]::EscapeDataString($Resource)
    if ($kind -eq 'himds') {
        $body = Invoke-BbHimds "http://localhost:40342/metadata/identity/oauth2/token?api-version=2019-11-01&$q"
    } else {
        $body = (Invoke-WebRequest -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&$q" -Headers @{ Metadata = 'true' } -UseBasicParsing -TimeoutSec 20).Content
    }
    $t = ($body | ConvertFrom-Json).access_token
    if (-not $t) { throw "no access token from $kind" }
    return @{ Token = $t; Source = $kind }
}

function Get-BbMachineInfo {
    # the machine's own Azure resource: subscription, resource group, name (prefix, CHOICE 3)
    $kind = Get-BbIdentityKind
    if ($kind -eq 'himds') {
        $cfgPath = Join-Path $env:ProgramData 'AzureConnectedMachineAgent\Config\agentconfig.json'
        $c = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
        $sub = $c.subscriptionId; $rg = $c.resourceGroup; $name = $c.resourceName
        $rid = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/$name"
    } else {
        $m = (Invoke-WebRequest -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01' -Headers @{ Metadata = 'true' } -UseBasicParsing -TimeoutSec 20).Content | ConvertFrom-Json
        $sub = $m.subscriptionId; $rg = $m.resourceGroupName; $name = $m.name; $rid = $m.resourceId
    }
    if (-not ($sub -and $rg -and $name)) { throw "machine metadata incomplete ($kind)" }
    [pscustomobject]@{ Kind = $kind; SubscriptionId = $sub; ResourceGroup = $rg; Name = $name; ResourceId = $rid
        Prefix = ("$sub/$rg/$name").ToLowerInvariant() }
}

function Get-BbBlobName {
    # <prefix>/<yyyy>/<mm>/<dd>/<machine>_<from yyyymmdd-hhmmss>_<to yyyymmdd-hhmmss>.zip (date = window end)
    param([Parameter(Mandatory)][string]$Prefix, [Parameter(Mandatory)][datetime]$From, [Parameter(Mandatory)][datetime]$To)
    $machine = $Prefix.TrimEnd('/').Split('/')[-1]
    return ('{0}/{1}/{2}_{3}_{4}.zip' -f $Prefix.TrimEnd('/').ToLowerInvariant(), $To.ToString('yyyy/MM/dd'), $machine,
        $From.ToString('yyyyMMdd-HHmmss'), $To.ToString('yyyyMMdd-HHmmss'))
}

function Get-BbMd5Base64 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { return [Convert]::ToBase64String($md5.ComputeHash($Bytes)) } finally { $md5.Dispose() }
}

function Get-BbSha256 {
    param([Parameter(Mandatory)][string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $fs = [System.IO.File]::OpenRead($Path)
    try { return (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $fs.Close(); $sha.Dispose() }
}

function Send-BbBlob {
    # REST upload with a bearer token (P26): Put Blob up to 32 MiB, else Put Block (8 MiB) + Put Block List.
    # Returns the HTTP status of the final call; throws on any failure.
    param([Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Container,
          [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Token,
          [hashtable]$Metadata = @{}, [int]$SingleMaxBytes = 32MB, [int]$BlockBytes = 8MB)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $base = "https://$Account.blob.core.windows.net/$Container/" + (($Name.Split('/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
    $h = @{ Authorization = "Bearer $Token"; 'x-ms-version' = '2023-11-03' }
    foreach ($k in $Metadata.Keys) { $h["x-ms-meta-$k"] = "$($Metadata[$k])" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $md5 = Get-BbMd5Base64 $bytes
    if ($bytes.Length -le $SingleMaxBytes) {
        $hh = $h.Clone(); $hh['x-ms-blob-type'] = 'BlockBlob'; $hh['Content-MD5'] = $md5
        $r = Invoke-WebRequest -Uri $base -Method Put -Headers $hh -Body $bytes -ContentType 'application/zip' -UseBasicParsing -TimeoutSec 300
        if ([int]$r.StatusCode -ne 201) { throw "Put Blob returned $($r.StatusCode)" }
        if ($r.Headers['Content-MD5'] -and $r.Headers['Content-MD5'] -ne $md5) { throw 'Put Blob: echoed MD5 differs' }
        return [int]$r.StatusCode
    }
    $ids = @()
    for ($off = 0; $off -lt $bytes.Length; $off += $BlockBytes) {
        $len = [math]::Min($BlockBytes, $bytes.Length - $off)
        $chunk = New-Object byte[] $len
        [Array]::Copy($bytes, $off, $chunk, 0, $len)
        $id = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('block-{0:D6}' -f $ids.Count)))
        $ids += $id
        $hb = @{ Authorization = $h.Authorization; 'x-ms-version' = $h['x-ms-version']; 'Content-MD5' = (Get-BbMd5Base64 $chunk) }
        $r = Invoke-WebRequest -Uri "$base`?comp=block&blockid=$([uri]::EscapeDataString($id))" -Method Put -Headers $hb -Body $chunk -UseBasicParsing -TimeoutSec 300
        if ([int]$r.StatusCode -ne 201) { throw "Put Block returned $($r.StatusCode)" }
    }
    $xml = '<?xml version="1.0" encoding="utf-8"?><BlockList>' + (($ids | ForEach-Object { "<Latest>$_</Latest>" }) -join '') + '</BlockList>'
    $hl = $h.Clone(); $hl['x-ms-blob-content-md5'] = $md5; $hl['x-ms-blob-content-type'] = 'application/zip'
    $r = Invoke-WebRequest -Uri "$base`?comp=blocklist" -Method Put -Headers $hl -Body ([Text.Encoding]::UTF8.GetBytes($xml)) -ContentType 'application/xml' -UseBasicParsing -TimeoutSec 300
    if ([int]$r.StatusCode -ne 201) { throw "Put Block List returned $($r.StatusCode)" }
    return [int]$r.StatusCode
}

# ---------- logging ----------

function Write-BbLog {
    param([Parameter(Mandatory)][string]$Message, [string]$Level = 'INFO')
    $p = Get-BbPaths
    if (-not (Test-Path -LiteralPath $p.Log)) { $null = New-Item -ItemType Directory -Force -Path $p.Log }
    $f = Join-Path $p.Log 'perfmonblackbox.log'
    if ((Test-Path -LiteralPath $f) -and (Get-Item -LiteralPath $f).Length -gt 5MB) { Move-Item -LiteralPath $f -Destination "$f.1" -Force }
    Add-Content -LiteralPath $f -Value ('{0} {1} {2}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $Level, $Message) -Encoding UTF8
}

function Write-BbEvent {
    # Application log, source PerfmonBlackbox: 1000 info, 2000 warning (data loss), 3000 error
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('Information', 'Warning', 'Error')][string]$EntryType = 'Information', [int]$EventId = 1000)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($script:BbEventSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($script:BbEventSource, 'Application')
        }
        [System.Diagnostics.EventLog]::WriteEntry($script:BbEventSource, $Message, $EntryType, $EventId)
    } catch {
        Write-BbLog "event log write failed: $($_.Exception.Message)" 'WARN'
    }
}

# ---------- collector lifecycle (start, roll, re-create, local cap) ----------

function Lock-Bb {
    # one machine-wide mutex for start, export and the DSC Set paths, so a roll never races a re-create
    param([int]$TimeoutSeconds = 600)
    $m = New-Object System.Threading.Mutex($false, 'Global\PerfmonBlackbox')
    try { $ok = $m.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds)) } catch [System.Threading.AbandonedMutexException] { $ok = $true }
    if (-not $ok) { $m.Dispose(); throw 'another PerfmonBlackbox operation holds the lock' }
    return $m
}

function Unlock-Bb {
    param($Mutex)
    if ($Mutex) { try { $Mutex.ReleaseMutex() } catch { } ; $Mutex.Dispose() }
}

function Stop-BbCollector {
    $r = Invoke-BbTool logman.exe @('stop', $script:BbSetName)
    # PLA needs a moment to close the file
    for ($i = 0; $i -lt 20; $i++) {
        $c = Get-BbCollector
        if (-not $c -or $c.Status -ne 'Running') { break }
        Start-Sleep -Milliseconds 500
    }
    return $r
}

function Start-BbCollector {
    $r = Invoke-BbTool logman.exe @('start', $script:BbSetName)
    if ($r.ExitCode -ne 0) { throw "logman start failed ($($r.ExitCode)): $($r.Output -join ' ')" }
    return $r
}

function Invoke-BbRoll {
    # stop -> move the ring to pending -> start (P21). Returns the stop and start times (the gap).
    param([Parameter(Mandatory)][string]$Reason)
    $t0 = Get-Date
    $null = Stop-BbCollector
    $moved = Move-BbBufferToPending -Reason $Reason
    Limit-BbLocalKeep
    $null = Start-BbCollector
    [pscustomobject]@{ Stopped = $t0; Started = (Get-Date); Moved = $moved }
}

function Install-BbCollector {
    # (re)create the set from the template; the current ring is kept as pending first (no sample lost)
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$BinDir)
    $collectorDir = Join-Path $BinDir 'collector'
    $counters = Get-BbExpectedCounters -CollectorDir $collectorDir
    $xml = New-BbCollectorXml -TemplatePath (Join-Path $collectorDir 'PerfmonBlackbox.template.xml') -Counters $counters `
        -MaxSizeMB $Config['MaxSizeMB'] -SampleIntervalSeconds $Config['SampleIntervalSeconds']
    $p = Get-BbPaths
    foreach ($d in $p.Blg, $p.Pending, $p.Work) { $null = New-Item -ItemType Directory -Force -Path $d }
    $file = Join-Path $p.Work 'PerfmonBlackbox.filled.xml'
    [System.IO.File]::WriteAllText($file, $xml, [System.Text.Encoding]::Unicode)
    if (Get-BbCollector) {
        $null = Stop-BbCollector
        $null = Move-BbBufferToPending -Reason 'recreate'
        $null = Invoke-BbTool logman.exe @('delete', $script:BbSetName)
    } else {
        $null = Move-BbBufferToPending -Reason 'recreate'
    }
    $r = Invoke-BbTool logman.exe @('import', '-n', $script:BbSetName, '-xml', $file)
    if ($r.ExitCode -ne 0) { throw "logman import failed ($($r.ExitCode)): $($r.Output -join ' ')" }
    Limit-BbLocalKeep
    $null = Start-BbCollector
    return $counters.Count
}

function Limit-BbLocalKeep {
    # LocalKeepMB caps pending buffers + outbox zips; the oldest pending go first and the loss is recorded in
    # state.local_cap_drops, so the next export reports it as a local_cap gap (never silent)
    $p = Get-BbPaths
    $cfg = $null
    try { $cfg = Get-BbConfig } catch { return }
    $limit = [int64]$cfg['LocalKeepMB'] * 1MB
    $files = @(Get-ChildItem -LiteralPath $p.Pending -Filter *.blg -ErrorAction SilentlyContinue | Sort-Object Name)
    $out = @(Get-ChildItem -LiteralPath $p.Outbox -ErrorAction SilentlyContinue)
    $total = [int64]0
    foreach ($f in ($files + $out)) { $total += $f.Length }
    if ($total -le $limit) { return }
    $state = Get-BbState
    $drops = @($state['local_cap_drops'])
    foreach ($f in $files) {
        if ($total -le $limit) { break }
        $info = Get-BbBlgInfo $f.FullName
        $drops += @{ file = $f.Name; from = $info.Begin; to = $info.End; bytes = $f.Length }
        Remove-Item -LiteralPath $f.FullName -Force
        $total -= $f.Length
        Write-BbEvent "PerfmonBlackbox: LocalKeepMB reached, pending buffer $($f.Name) ($($info.Begin) .. $($info.End)) deleted unexported" 'Warning' 2001
    }
    $state['local_cap_drops'] = $drops
    Write-BbJson (Get-BbPaths).State $state
}

# ---------- scheduled tasks (schtasks.exe + task XML; the ScheduledTasks module is not loadable by the agent) ----------

$script:BbTaskFolder = '\PerfmonBlackbox'

function New-BbTaskXml {
    # Boot: at startup. Export: daily, repeated every ExportEveryHours (24 = once a day), StartWhenAvailable.
    # Both: SYSTEM (S-1-5-18), highest run level, Windows PowerShell 5.1.
    param([Parameter(Mandatory)][ValidateSet('Boot', 'Export')][string]$Kind, [Parameter(Mandatory)][string]$BinDir,
          [int]$ExportEveryHours = 4)
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ($Kind -eq 'Boot') {
        $trigger = '<BootTrigger><Enabled>true</Enabled><Delay>PT30S</Delay></BootTrigger>'
        $script = Join-Path $BinDir 'Start-PerfmonBlackbox.ps1'
        $taskArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" -Reason boot"
        $limit = 'PT10M'
    } else {
        $rep = ''
        if ($ExportEveryHours -lt 24) { $rep = "<Repetition><Interval>PT$($ExportEveryHours)H</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition>" }
        $trigger = "<CalendarTrigger>$rep<StartBoundary>2026-01-01T00:07:00</StartBoundary><Enabled>true</Enabled><RandomDelay>PT10M</RandomDelay><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>"
        $script = Join-Path $BinDir 'Export-PerfmonBlackbox.ps1'
        $taskArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`""
        $limit = 'PT2H'
    }
    $esc = [System.Security.SecurityElement]::Escape($taskArgs)
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Author>PerfmonBlackbox</Author><Description>PerfmonBlackbox $Kind (Azure Machine Configuration package; do not edit)</Description></RegistrationInfo>
  <Triggers>$trigger</Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>$limit</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>$ps</Command><Arguments>$esc</Arguments></Exec></Actions>
</Task>
"@
}

function Get-BbTask {
    # the registered task as XML, or $null
    param([Parameter(Mandatory)][ValidateSet('Boot', 'Export')][string]$Kind)
    $r = Invoke-BbTool schtasks.exe @('/query', '/tn', "$script:BbTaskFolder\$Kind", '/xml')
    if ($r.ExitCode -ne 0) { return $null }
    return [xml](($r.Output -join "`n") -replace '^\s*<\?xml[^>]*\?>', '')
}

function Compare-BbTask {
    # reasons why the registered task differs from the expected one (empty = compliant)
    param([Parameter(Mandatory)][string]$Kind, $Actual, [Parameter(Mandatory)][string]$ExpectedXml)
    if (-not $Actual) { return , @("task $script:BbTaskFolder\$Kind is not registered") }
    $exp = [xml]($ExpectedXml -replace '^\s*<\?xml[^>]*\?>', '')
    $ns = New-Object System.Xml.XmlNamespaceManager $exp.NameTable
    $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    $r = @()
    $checks = @(
        @('principal', 't:Task/t:Principals/t:Principal/t:UserId'),
        @('run level', 't:Task/t:Principals/t:Principal/t:RunLevel'),
        @('command', 't:Task/t:Actions/t:Exec/t:Command'),
        @('arguments', 't:Task/t:Actions/t:Exec/t:Arguments'),
        @('start when available', 't:Task/t:Settings/t:StartWhenAvailable'),
        @('enabled', 't:Task/t:Settings/t:Enabled'),
        @('boot trigger', 't:Task/t:Triggers/t:BootTrigger'),
        @('repetition', 't:Task/t:Triggers/t:CalendarTrigger/t:Repetition/t:Interval'),
        @('daily', 't:Task/t:Triggers/t:CalendarTrigger/t:ScheduleByDay/t:DaysInterval'))
    $ns2 = New-Object System.Xml.XmlNamespaceManager $Actual.NameTable
    $ns2.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    foreach ($c in $checks) {
        $e = $exp.SelectSingleNode($c[1], $ns); $a = $Actual.SelectSingleNode($c[1], $ns2)
        $ev = ''; $av = ''
        if ($e) { $ev = $e.InnerText; if ($c[0] -eq 'boot trigger') { $ev = 'present' } }
        if ($a) { $av = $a.InnerText; if ($c[0] -eq 'boot trigger') { $av = 'present' } }
        # schtasks /query /xml leaves out elements at their default (Enabled = true)
        if ($c[0] -eq 'enabled' -and $av -eq '') { $av = 'true' }
        if ($c[0] -eq 'principal' -and $av -eq 'SYSTEM') { $av = 'S-1-5-18' }
        if ($ev -ne $av) { $r += "task $Kind`: $($c[0]) is '$av', expected '$ev'" }
    }
    return , $r
}

function Register-BbTask {
    param([Parameter(Mandatory)][string]$Kind, [Parameter(Mandatory)][string]$Xml)
    $p = Get-BbPaths
    $null = New-Item -ItemType Directory -Force -Path $p.Work
    $file = Join-Path $p.Work "task-$Kind.xml"
    [System.IO.File]::WriteAllText($file, $Xml, [System.Text.Encoding]::Unicode)
    $r = Invoke-BbTool schtasks.exe @('/create', '/tn', "$script:BbTaskFolder\$Kind", '/xml', $file, '/f')
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) { throw "schtasks /create $Kind failed ($($r.ExitCode)): $($r.Output -join ' ')" }
}

# ---------- folder ACL (icacls.exe; SIDs, so it works on any OS language) ----------

$script:BbSddl = 'D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'

function Test-BbSddl {
    # same protected DACL with the same ACEs, in any order (icacls keeps its own ACE order)
    param([string]$Actual, [string]$Expected = $script:BbSddl)
    if (-not $Actual) { return $false }
    $norm = {
        param($x)
        if ($x -notmatch '^D:(?<flags>[A-Z]*)(?<aces>\(.*\))$') { return $null }
        $aces = [regex]::Matches($Matches.aces, '\([^)]*\)') | ForEach-Object { $_.Value } | Sort-Object
        return ($Matches.flags + '|' + ($aces -join ''))
    }
    return ((& $norm $Actual) -and (& $norm $Actual) -eq (& $norm $Expected))
}

function Get-BbAclSddl {
    param([Parameter(Mandatory)][string]$Path)
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        $r = Invoke-BbTool icacls.exe @($Path, '/save', $tmp)
        if ($r.ExitCode -ne 0) { return $null }
        $lines = [System.IO.File]::ReadAllLines($tmp, [System.Text.Encoding]::Unicode)
        if ($lines.Count -ge 2) { return $lines[1].Trim() }
        return $null
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Set-BbAcl {
    # SYSTEM + Administrators only, inheritance off (captures carry process and instance names)
    param([Parameter(Mandatory)][string]$Path)
    $r = Invoke-BbTool icacls.exe @($Path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '/T', '/C', '/Q')
    if ($r.ExitCode -ne 0) { throw "icacls failed ($($r.ExitCode)): $($r.Output -join ' ')" }
    # drop every other ACE that came with the folder (e.g. Users, CREATOR OWNER)
    foreach ($sid in '*S-1-5-32-545', '*S-1-3-0', '*S-1-5-11') { $null = Invoke-BbTool icacls.exe @($Path, '/remove:g', $sid, '/T', '/C', '/Q') }
}

# ---------- export (design sec. 2.2; the Export task runs Export-PerfmonBlackbox.ps1, which calls this) ----------

function Invoke-BbExport {
    # -NoRoll/-NoLock/-Machine/-Uploader/-CollectorDir exist for the Pester tests (L05) and the lab; the task uses none
    param([switch]$NoUpload, [switch]$NoRoll, [switch]$NoLock, $Machine, [scriptblock]$Uploader,
          [string]$CollectorDir = (Join-Path (Get-BbPaths).Bin 'collector'), [string]$PackageVersion = '1.0.0')
    $StampFormat = 'yyyy-MM-dd HH:mm:ss.fff'
    $p = Get-BbPaths
    $lock = $null
    if (-not $NoLock) { $lock = Lock-Bb }
    $work = $null
    try {
        $cfg = Get-BbConfig
        $state = Get-BbState
        $iv = $cfg['SampleIntervalSeconds']
        $lastTs = $null
        if ($state['last_ts']) { $lastTs = [datetime]::ParseExact($state['last_ts'], $StampFormat, [Globalization.CultureInfo]::InvariantCulture) }
        if (-not $Machine) { $Machine = Get-BbMachineInfo }
        $machine = $Machine
        $account = ($cfg['StorageAccountResourceId'].TrimEnd('/') -split '/')[-1]

        # 1 roll
        $rollSeconds = 0
        if (-not $NoRoll) {
            $roll = Invoke-BbRoll -Reason 'export'
            $rollSeconds = [math]::Round(($roll.Started - $roll.Stopped).TotalSeconds, 1)
        }

        # 2 relog each pending buffer, oldest first
        $work = Join-Path $p.Work ('export-' + (Get-Date).ToString('yyyyMMddHHmmss'))
        $null = New-Item -ItemType Directory -Force -Path $work
        $pending = @(Get-ChildItem -LiteralPath $p.Pending -Filter *.blg -ErrorAction SilentlyContinue | Sort-Object Name)
        $parts = @(); $partInfo = @(); $partFiles = @(); $unreadable = @()
        $fmt = $null
        foreach ($f in $pending) {
            $csv = Join-Path $work ($f.BaseName + '.csv')
            $r = Invoke-BbTool relog.exe @($f.FullName, '-f', 'csv', '-o', $csv, '-y')
            if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $csv)) { $unreadable += $f.Name; continue }
            $part = Read-BbCsv -Path $csv -Format $fmt
            $fmt = $part.Format
            if (-not $part.Rows.Count) { $unreadable += $f.Name; continue }
            $parts += $part
            $partFiles += $f
            $partInfo += [pscustomobject]@{ Name = $f.Name; Reason = (Get-BbPendingReason $f.Name); Bytes = $f.Length
                Rows = $part.Rows.Count; Wrapped = ($f.Length -ge 0.95 * $cfg['MaxSizeMB'] * 1MB) }
        }
        if ($unreadable.Count) { Write-BbLog "unreadable pending buffers kept for the next run: $($unreadable -join ', ')" 'WARN' }

        # capacity: bytes per sample of the newest buffer with enough samples (R6 reads it from state.json)
        $meas = $partInfo | Where-Object { $_.Rows -ge 30 } | Select-Object -Last 1
        if ($meas) {
            $state['bytes_per_sample'] = [int]($meas.Bytes / $meas.Rows)
            $state['buffer_hours'] = Get-BbBufferHours $state['bytes_per_sample'] $cfg['MaxSizeMB'] $iv
            $state['processes'] = @(Get-Process).Count
        }
        if (-not $parts.Count) {
            Write-BbLog 'export: no readable pending buffer, nothing to export'
            Write-BbJson $p.State $state
            return [pscustomobject]@{ Result = 'nothing'; Rows = 0 }
        }

        # 2b merge, no overlap with the last export
        $merged = Merge-BbCsv -Parts $parts -After $lastTs
        $rows = $merged.Rows
        if (-not $rows.Count) {
            Write-BbLog 'export: no sample after last_ts'
            foreach ($f in $partFiles) { Remove-Item -LiteralPath $f.FullName -Force }
            Write-BbJson $p.State $state
            return [pscustomobject]@{ Result = 'nothing'; Rows = 0 }
        }
        $first = $rows[0].Time; $last = $rows[$rows.Count - 1].Time

        # 3 holes
        $gaps = Find-BbGaps -Rows $rows -IntervalSeconds $iv -LastTs $lastTs -PartInfo $partInfo -Drops @($state['local_cap_drops'])
        $complete = ($gaps.Count -eq 0)

        # 4 validate
        $required = @(Read-BbCounterFile (Join-Path $CollectorDir 'PerfmonBlackbox.counters.txt'))
        $bad = Test-BbCsv -Merged $merged -Required $required -WindowFrom $lastTs
        if ($bad.Count) { throw "CSV validation failed: $($bad -join '; ')" }

        # 5 CSV + manifest + zip
        $base = '{0}_{1}_{2}' -f $machine.Name.ToLowerInvariant(), $first.ToString('yyyyMMdd-HHmmss'), $last.ToString('yyyyMMdd-HHmmss')
        $csvPath = Join-Path $work "$base.csv"
        Write-BbCsv -Merged $merged -Path $csvPath
        $winFrom = $first
        if ($lastTs) { $winFrom = $lastTs }
        $offset = [TimeZoneInfo]::Local.GetUtcOffset($last)
        $manifest = [ordered]@{
            schema = 'perfmon-blackbox/manifest/1'
            package_version = $PackageVersion
            machine_prefix = $machine.Prefix
            resource_id = $machine.ResourceId
            identity = $machine.Kind
            seq = [int]$state['seq'] + 1
            window_from = $winFrom.ToString($StampFormat)
            window_to = $last.ToString($StampFormat)
            first_sample = $first.ToString($StampFormat)
            last_sample = $last.ToString($StampFormat)
            utc_offset = ('{0}{1:hh\:mm}' -f $(if ($offset -lt [TimeSpan]::Zero) { '-' } else { '+' }), $offset)
            rows = $rows.Count
            columns = $merged.Columns.Count
            interval_s = $iv
            max_size_mb = $cfg['MaxSizeMB']
            export_every_hours = $cfg['ExportEveryHours']
            buffer_hours = $state['buffer_hours']
            bytes_per_sample = $state['bytes_per_sample']
            processes = $state['processes']
            roll_seconds = $rollSeconds
            sources = @($partInfo | ForEach-Object { [ordered]@{ name = $_.Name; reason = $_.Reason; bytes = $_.Bytes; rows = $_.Rows; wrapped = $_.Wrapped } })
            gaps = @($gaps)
            complete = $complete
            csv_name = "$base.csv"
            csv_sha256 = (Get-BbSha256 $csvPath)
        }
        Write-BbJson (Join-Path $work 'manifest.json') $manifest
        $null = New-Item -ItemType Directory -Force -Path $p.Outbox
        # a zip left by a failed upload is superseded: this window starts at the same last_ts
        Get-ChildItem -LiteralPath $p.Outbox -Filter *.zip -ErrorAction SilentlyContinue | Remove-Item -Force
        $zipPath = Join-Path $p.Outbox "$base.zip"
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zt0 = Get-Date
        $z = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, $csvPath, "$base.csv", [System.IO.Compression.CompressionLevel]::Optimal)
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, (Join-Path $work 'manifest.json'), 'manifest.json', [System.IO.Compression.CompressionLevel]::Optimal)
        } finally { $z.Dispose() }
        $zipSeconds = [math]::Round(((Get-Date) - $zt0).TotalSeconds, 1)
        $zipBytes = (Get-Item -LiteralPath $zipPath).Length
        $blob = Get-BbBlobName -Prefix $machine.Prefix -From $first -To $last
        Write-BbLog "export: $($rows.Count) rows $($first.ToString($StampFormat)) .. $($last.ToString($StampFormat)), gaps $($gaps.Count), roll $rollSeconds s, csv $((Get-Item -LiteralPath $csvPath).Length) B, zip $zipBytes B in $zipSeconds s -> $blob"

        $result = [pscustomobject]@{ Result = 'built'; Rows = $rows.Count; Blob = $blob; Zip = $zipPath; Manifest = $manifest; ZipSeconds = $zipSeconds; ZipBytes = $zipBytes }
        if ($NoUpload) { Write-BbLog 'export: -NoUpload, zip left in outbox, state unchanged'; return $result }

        # 6 token, 7 upload (a test passes -Uploader instead)
        $meta = @{ sha256 = (Get-BbSha256 $zipPath); seq = $manifest.seq; complete = "$complete".ToLowerInvariant() }
        if ($Uploader) {
            $status = & $Uploader $blob $zipPath $meta
        } else {
            $tok = Get-BbToken
            $status = Send-BbBlob -Account $account -Container $cfg['ContainerName'] -Name $blob -Path $zipPath -Token $tok.Token -Metadata $meta
            $tok = $null
        }
        if ([int]$status -ne 201) { throw "upload returned $status" }

        # 8 commit: only after a verified upload
        $state['last_ts'] = $last.ToString($StampFormat)
        $state['seq'] = $manifest.seq
        $state['last_export_utc'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $state['last_blob'] = $blob
        $state['last_error'] = $null
        $state['local_cap_drops'] = @()
        Write-BbJson $p.State $state
        foreach ($f in $partFiles) { Remove-Item -LiteralPath $f.FullName -Force }
        Remove-Item -LiteralPath $zipPath -Force
        Write-BbLog "export: uploaded ($status) with $($machine.Kind) identity, seq $($manifest.seq), complete $complete"
        if ($complete) {
            Write-BbEvent "PerfmonBlackbox export $($manifest.seq) uploaded: $blob ($($rows.Count) samples, complete)" 'Information' 1002
        } else {
            $g = ($gaps | ForEach-Object { "$($_.cause) $($_.from)..$($_.to)" }) -join '; '
            Write-BbEvent "PerfmonBlackbox export $($manifest.seq) uploaded INCOMPLETE: $blob; gaps: $g" 'Warning' 2002
        }
        $result.Result = 'uploaded'
        return $result
    } catch {
        $msg = $_.Exception.Message
        Write-BbLog "export failed: $msg" 'ERROR'
        Write-BbEvent "PerfmonBlackbox export failed (state unchanged, the next run retries the window): $msg" 'Error' 3002
        try { $s = Get-BbState; $s['last_error'] = $msg; Write-BbJson $p.State $s } catch { }
        throw
    } finally {
        if ($work -and (Test-Path -LiteralPath $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
        Unlock-Bb $lock
    }
}
