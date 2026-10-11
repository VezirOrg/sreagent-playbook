# T08 in-guest (Windows PowerShell 5.1): after a reboot the collector runs again, the Boot task ran after the boot
# with result 0, and the pre-reboot ring was kept as a pending buffer (*-boot.blg).
$ErrorActionPreference = 'Stop'
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$inf = & schtasks.exe /query /tn '\PerfmonBlackbox\Boot' /v /fo csv | ConvertFrom-Csv | Select-Object -First 1
$c = Get-BbCollector
$pend = @(Get-ChildItem C:\ProgramData\PerfmonBlackbox\pending -Filter '*-boot.blg' -ErrorAction SilentlyContinue)
$up = ((Get-Date) - $boot).TotalMinutes
"boot $($boot.ToString('yyyy-MM-dd HH:mm:ss')) ($([int]$up) min ago); boot task last run $($inf.'Last Run Time') result $($inf.'Last Result'); collector $($c.Status); boot buffers pending $($pend.Count)"
$fail = 0
if ($c.Status -ne 'Running') { $fail = 1 }
if ("$($inf.'Last Result')" -ne '0' -or [datetime]::Parse($inf.'Last Run Time') -lt $boot) { $fail = 1 }
if (-not $pend.Count) { $fail = 1 }
if ($fail) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
