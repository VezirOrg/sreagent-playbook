# T06 in-guest (Windows PowerShell 5.1): the collector equals 36 + G1 + G2 (+ present G3), binary circular,
# interval and size from config.json, no duration limit, Running, and the .blg grows. Prints RESULT: PASS|FAIL.
$ErrorActionPreference = 'Stop'
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
$cfg = Get-BbConfig
$exp = Get-BbExpectedCounters -CollectorDir 'C:\ProgramData\PerfmonBlackbox\bin\collector'
$c = Get-BbCollector
$fail = 0
"status=$($c.Status) counters=$($c.Counters.Count) expected=$($exp.Count) interval=$($c.SampleIntervalSeconds) maxMB=$($c.MaxSizeMB) circular=$($c.Circular) binary=$($c.BinaryFormat) duration=$($c.Duration)"
"config: MaxSizeMB=$($cfg['MaxSizeMB']) SampleIntervalSeconds=$($cfg['SampleIntervalSeconds']) ExportEveryHours=$($cfg['ExportEveryHours'])"
$g3 = @($exp | Where-Object { (Get-BbCounterObject $_) -in $script:BbG3Objects })
"G3 configured: $($g3.Count) (objects present: $((@($script:BbG3Objects | Where-Object { Test-BbCounterObject $_ })) -join ', '))"
foreach ($r in (Compare-BbCollector -Collector $c -Expected $exp -MaxSizeMB $cfg['MaxSizeMB'] -SampleIntervalSeconds $cfg['SampleIntervalSeconds'])) { "DIFF $r"; $fail = 1 }
if ($c.Status -ne 'Running') { 'NOT RUNNING'; $fail = 1 }
$f = Get-ChildItem C:\ProgramData\PerfmonBlackbox\blg -Filter *.blg | Select-Object -First 1
$s1 = $f.Length
Start-Sleep -Seconds ([Math]::Max(25, 2 * $cfg['SampleIntervalSeconds'] + 5))
$s2 = (Get-Item $f.FullName).Length
"blg bytes: $s1 -> $s2 (max $($cfg['MaxSizeMB'] * 1MB))"
if ($s2 -le $s1 -and $s2 -lt 0.99 * $cfg['MaxSizeMB'] * 1MB) { 'NOT GROWING'; $fail = 1 }
if ($s2 -gt $cfg['MaxSizeMB'] * 1MB) { 'ABOVE MaxSizeMB'; $fail = 1 }
if ($fail) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
