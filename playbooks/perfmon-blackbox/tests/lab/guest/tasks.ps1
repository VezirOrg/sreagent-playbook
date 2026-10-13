# T07 in-guest (Windows PowerShell 5.1): exactly the Boot, Export and Roll (P62) tasks under \PerfmonBlackbox\, as expected;
# each run on demand, then Last Result 0 and Last Run Time after the start. Prints RESULT: PASS|FAIL.
param([switch]$NoRun)
$ErrorActionPreference = 'Stop'
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
$cfg = Get-BbConfig
$bin = 'C:\ProgramData\PerfmonBlackbox\bin'
$fail = 0
$all = @(& schtasks.exe /query /fo csv /nh | ConvertFrom-Csv -Header TaskName, Next, Status | Where-Object { $_.TaskName -like '\PerfmonBlackbox\*' } | ForEach-Object TaskName | Sort-Object -Unique)
"tasks under \PerfmonBlackbox\: $($all -join ', ')"
if (($all -join ',') -ne '\PerfmonBlackbox\Boot,\PerfmonBlackbox\Export,\PerfmonBlackbox\Roll') { 'UNEXPECTED TASK SET'; $fail = 1 }
foreach ($k in 'Boot', 'Export', 'Roll') {
    $exp = New-BbTaskXml -Kind $k -BinDir $bin -ExportEveryHours $cfg['ExportEveryHours']
    foreach ($r in (Compare-BbTask -Kind $k -Actual (Get-BbTask $k) -ExpectedXml $exp)) { "DIFF $r"; $fail = 1 }
}
function Info($k) { & schtasks.exe /query /tn "\PerfmonBlackbox\$k" /v /fo csv | ConvertFrom-Csv | Select-Object -First 1 }
if (-not $NoRun) {
    foreach ($k in 'Boot', 'Roll', 'Export') {
        $t0 = Get-Date
        $null = & schtasks.exe /run /tn "\PerfmonBlackbox\$k"
        Start-Sleep 5
        for ($i = 0; $i -lt 120; $i++) { if ((Info $k).Status -ne 'Running') { break }; Start-Sleep 5 }
        $inf = Info $k
        $last = [datetime]::Parse($inf.'Last Run Time')
        "$k`: last run $($inf.'Last Run Time') result $($inf.'Last Result') principal $($inf.'Run As User')"
        if ("$($inf.'Last Result')" -ne '0') { "$k RESULT NOT 0"; $fail = 1 }
        if ($last -lt $t0.AddSeconds(-60)) { "$k DID NOT RUN"; $fail = 1 }
    }
    Get-Content C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log -Tail 4
}
if ($fail) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
