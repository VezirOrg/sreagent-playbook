# T06b/T06c in-guest (Windows PowerShell 5.1): poll the live .blg size every 30 s for -Minutes; print the max and
# whether it reached the MaxSizeMB of config.json (>= 95 %) and never exceeded it. RESULT: PASS|FAIL.
param([int]$Minutes = 15, [int]$MinMB = 0)
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
$cfg = Get-BbConfig; $max = $cfg['MaxSizeMB'] * 1MB
$peak = 0; $fullAt = $null; $t0 = Get-Date
while (((Get-Date) - $t0).TotalMinutes -lt $Minutes) {
    $f = Get-ChildItem C:\ProgramData\PerfmonBlackbox\blg -Filter *.blg -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { if ($f.Length -gt $peak) { $peak = $f.Length }; if (-not $fullAt -and $f.Length -ge 0.95 * $max) { $fullAt = Get-Date } }
    Start-Sleep 30
}
$c = Get-BbCollector
"MaxSizeMB $($cfg['MaxSizeMB']) interval $($cfg['SampleIntervalSeconds']) s; collector max $($c.MaxSizeMB) MB; peak $peak B; full at $(if ($fullAt) { $fullAt.ToString('HH:mm:ss') } else { 'never' }); now $((Get-Date).ToString('HH:mm:ss'))"
$ok = ($peak -le $max) -and $fullAt -and ($c.MaxSizeMB -eq $cfg['MaxSizeMB']) -and ($peak -ge $MinMB * 1MB)
if ($ok) { 'RESULT: PASS' } else { 'RESULT: FAIL' }
