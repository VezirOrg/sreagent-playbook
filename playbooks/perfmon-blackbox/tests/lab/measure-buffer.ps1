<#
measure-buffer.ps1: lab measurements for the PerfmonBlackbox circular .blg (decisions P16, P18; tests T07b).

Runs on the lab machine as an administrator (Windows PowerShell 5.1). Actions:
  setup   -IntervalSeconds <s> -MaxSizeMB <mb> [-SetName <n>] [-ExtraCounterFiles <f1,f2>]
          fill the template's placeholders, add the extra counter groups (if any), import the set, start it
  sample  [-SetName <n>]     one CSV line: utc, file bytes, processes, Process(*) instances, status (a running
                             circular .blg cannot be read, so no sample count here)
  readback [-SetName <n>]    stop the set and read the closed file: bytes, samples, first/last sample
  recorded [-SetName <n>]    counters recorded in the current .blg, counted per object
  detect                     which G3 (web) counter objects exist on this machine
  events  -Since <utc ISO>   new events since then, per log / provider / id / level (Application, System, PLA Operational)
  load    -Count <n>         start n idle helper processes (to vary the process count)
  unload                     stop the helper processes
  stop    [-SetName <n>]     stop and delete the collector set (the .blg stays)
Prints facts only.
#>
param(
    [Parameter(Mandatory)][ValidateSet('setup', 'sample', 'readback', 'recorded', 'detect', 'events', 'load', 'unload', 'stop')][string]$Action,
    [string]$SetName = 'PerfmonBlackbox',
    [string]$TemplatePath = 'C:\ProgramData\PerfmonBlackbox\PerfmonBlackbox.template.xml',
    [string[]]$ExtraCounterFiles = @(),
    [int]$IntervalSeconds = 1,
    [int]$MaxSizeMB = 512,
    [int]$Count = 100,
    [string]$Since = ''
)
$ErrorActionPreference = 'Stop'
# powershell -File passes 'a,b' as one string: split it
$ExtraCounterFiles = @($ExtraCounterFiles | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Root = Join-Path $env:ProgramData 'PerfmonBlackbox'
$BlgDir = Join-Path $Root "blg-$SetName"

function Get-Blg { Get-ChildItem -Path $BlgDir -Filter *.blg -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 }
function Read-Counters($path) { Get-Content $path | Where-Object { $_ -and -not $_.StartsWith('#') } }

switch ($Action) {
    'setup' {
        New-Item -ItemType Directory -Force -Path $BlgDir | Out-Null
        $xml = (Get-Content -Raw -Encoding UTF8 $TemplatePath).Replace('{{MaxSizeMB}}', "$MaxSizeMB").Replace('{{SampleIntervalSeconds}}', "$IntervalSeconds")
        $xml = $xml.Replace('<Name>PerfmonBlackbox</Name>', "<Name>$SetName</Name>").Replace('\PerfmonBlackbox\blg<', "\PerfmonBlackbox\blg-$SetName<")
        $extra = @(); foreach ($f in $ExtraCounterFiles) { $extra += Read-Counters (Join-Path $Root $f) }
        if ($extra.Count) {
            $add = ($extra | ForEach-Object { "`t`t<Counter>$([Security.SecurityElement]::Escape($_))</Counter>`r`n" }) -join ''
            $xml = $xml.Replace("`t</PerformanceCounterDataCollector>", "$add`t</PerformanceCounterDataCollector>")
        }
        if ($xml -match '\{\{(MaxSizeMB|SampleIntervalSeconds)\}\}') { throw 'unfilled placeholder in the template' }
        $filled = Join-Path $env:TEMP "$SetName.filled.xml"
        # logman import reads the XML as written by PerfMon (UTF-16); same content, only the encoding differs
        $xml.Replace('encoding="UTF-8"', 'encoding="UTF-16"') | Out-File -FilePath $filled -Encoding Unicode
        & logman stop $SetName 2>$null | Out-Null
        & logman delete $SetName 2>$null | Out-Null
        $out = & logman import -n $SetName -xml $filled 2>&1
        "import exit=$LASTEXITCODE :: $($out -join ' ')"
        if ($LASTEXITCODE -ne 0) { exit 2 }
        $out = & logman start $SetName 2>&1
        "start exit=$LASTEXITCODE :: $($out -join ' ')"
        if ($LASTEXITCODE -ne 0) { exit 3 }
        $pla = New-Object -ComObject Pla.DataCollectorSet
        $pla.Query($SetName, $null)
        $dc = $pla.DataCollectors.Item(0)
        "pla: set=$SetName status=$($pla.Status) segmentMaxSizeMB=$($pla.SegmentMaxSize) duration=$($pla.Duration) logCircular=$($dc.LogCircular) logFileFormat=$($dc.LogFileFormat) sampleInterval=$($dc.SampleInterval) countersConfigured=$($dc.PerformanceCounters.Count) extraCounters=$($extra.Count)"
    }
    'sample' {
        # A running circular .blg cannot be read (relog: "Unable to read counter information"), not even a copy:
        # while it runs only its size is sampled; samples come from elapsed time / interval, checked by 'readback'.
        $f = Get-Blg
        $bytes = if ($f) { $f.Length } else { 0 }
        $procs = (Get-Process).Count
        $inst = ((Get-Counter '\Process(*)\ID Process' -ErrorAction SilentlyContinue).CounterSamples).Count
        $status = ((& logman query $SetName) -match '^Status:' | Select-Object -First 1) -replace '^Status:\s*', ''
        '{0},{1},{2},,,,{3},{4},{5}' -f $SetName, (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $bytes, $procs, $inst, $status.Trim()
    }
    'readback' {
        # stop the set, then read the closed file: true samples, first and last sample (UTC on the lab VMs)
        & logman stop $SetName 2>&1 | Out-Null
        Start-Sleep 3
        $f = Get-Blg
        $samples = ''; $first = ''; $last = ''
        foreach ($l in (& relog $f.FullName -q 2>&1)) {
            if ($l -match '^\s*Samples:\s*(\d+)') { $samples = $Matches[1] }
            elseif ($l -match '^\s*Begin:\s*(.+)$') { $first = $Matches[1].Trim() }
            elseif ($l -match '^\s*End:\s*(.+)$') { $last = $Matches[1].Trim() }
        }
        '{0},{1},{2},{3},{4},{5},{6},{7},stopped' -f $SetName, (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $f.Length, $samples, $first, $last, (Get-Process).Count, ((Get-Counter '\Process(*)\ID Process' -ErrorAction SilentlyContinue).CounterSamples).Count
    }
    'recorded' {
        $f = Get-Blg
        $tmp = Join-Path $env:TEMP "$SetName.counters.txt"
        Remove-Item -Force -ErrorAction SilentlyContinue $tmp
        & relog $f.FullName -q -o $tmp | Out-Null
        $paths = Get-Content $tmp | Where-Object { $_ -match '^\\\\' }
        "recorded counter instances: $($paths.Count)"
        $paths | ForEach-Object { ($_ -split '\\')[3] -replace '\(.*$', '' } | Group-Object | Sort-Object Name |
            ForEach-Object { '{0}: {1}' -f $_.Name, $_.Count }
    }
    'detect' {
        foreach ($set in 'ASP.NET', 'ASP.NET Applications', '.NET CLR Memory', 'Web Service') {
            $ok = [bool](Get-Counter -ListSet $set -ErrorAction SilentlyContinue)
            "$set exists=$ok"
        }
        "IIS (W3SVC) installed=$([bool](Get-Service W3SVC -ErrorAction SilentlyContinue))"
    }
    'events' {
        $t0 = [datetime]::Parse($Since).ToUniversalTime()
        foreach ($log in 'Application', 'System', 'Microsoft-Windows-Diagnosis-PLA/Operational') {
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $t0.ToLocalTime() } -ErrorAction SilentlyContinue)
            if (-not $ev.Count) { "$log|-|-|-|0"; continue }
            $ev | Group-Object ProviderName, Id, LevelDisplayName | ForEach-Object { "$log|$($_.Name -replace ', ', '|')|$($_.Count)" }
        }
    }
    'load' {
        1..$Count | ForEach-Object { Start-Process -FilePath "$env:SystemRoot\System32\ping.exe" -ArgumentList '-n', '86400', '127.0.0.1' -WindowStyle Hidden }
        "started $Count helpers; processes now $((Get-Process).Count)"
    }
    'unload' {
        Get-Process -Name ping -ErrorAction SilentlyContinue | Stop-Process -Force
        "helpers stopped; processes now $((Get-Process).Count)"
    }
    'stop' {
        & logman stop $SetName 2>&1 | Out-Null
        & logman delete $SetName 2>&1 | Out-Null
        "stopped and deleted $SetName"
    }
}
