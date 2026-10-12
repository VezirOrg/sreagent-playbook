# Run the Export task on demand (as SYSTEM, like the schedule does), wait for it, print its result and the state.
# Windows PowerShell 5.1. Prints RESULT: PASS|FAIL (PASS = task result 0).
#   -MaxWaitSeconds: how long to wait for the task (a blocked upload retries for >= 15 min since rc.8, P46)
#   -StartOnly: start the task and return at once (T10d lifts the block while the run is still retrying)
param([int]$MaxWaitSeconds = 900, [switch]$StartOnly)
$ErrorActionPreference = 'Stop'
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
function Info { & schtasks.exe /query /tn '\PerfmonBlackbox\Export' /v /fo csv | ConvertFrom-Csv | Select-Object -First 1 }
$t0 = Get-Date
$null = & schtasks.exe /run /tn '\PerfmonBlackbox\Export'
Start-Sleep 5
if ($StartOnly) { "export task: started $($t0.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')), status $((Info).Status)"; return }
for ($i = 0; $i -lt [int]($MaxWaitSeconds / 5); $i++) { if ((Info).Status -ne 'Running') { break }; Start-Sleep 5 }
$inf = Info
$s = Get-BbState
"export task: result $($inf.'Last Result') after $([int]((Get-Date) - $t0).TotalSeconds) s"
"state: seq=$($s['seq']) last_ts=$($s['last_ts']) buffer_hours=$($s['buffer_hours']) bytes_per_sample=$($s['bytes_per_sample']) processes=$($s['processes']) last_error=$($s['last_error'])"
"last_blob: $($s['last_blob'])"
"collector: $((Get-BbCollector).Status); pending: $(@(Get-ChildItem C:\ProgramData\PerfmonBlackbox\pending -Filter *.blg -ErrorAction SilentlyContinue).Count); outbox: $(@(Get-ChildItem C:\ProgramData\PerfmonBlackbox\outbox -ErrorAction SilentlyContinue).Count)"
Get-Content C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log -Tail 3
if ("$($inf.'Last Result')" -eq '0') { 'RESULT: PASS' } else { 'RESULT: FAIL' }
