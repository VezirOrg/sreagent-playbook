# T07b in-guest (Windows PowerShell 5.1): the measured fill rate in state.json (bytes per sample of the last closed
# ring with >= 30 samples), the buffer hours it gives at MaxSizeMB and the interval, and the process count; PASS when
# the buffer holds >= 1.5 x ExportEveryHours. Also the formula estimate (P27) for comparison.
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
$cfg = Get-BbConfig; $s = Get-BbState; $p = @(Get-Process).Count
$est = Get-BbEstimatedBytesPerSample $p
"measured bytes/sample $($s['bytes_per_sample']) (processes then $($s['processes'])); buffer hours $($s['buffer_hours']) at $($cfg['SampleIntervalSeconds']) s, MaxSizeMB $($cfg['MaxSizeMB']); export every $($cfg['ExportEveryHours']) h"
"formula estimate now: $est bytes/sample at $p processes -> $(Get-BbBufferHours $est $cfg['MaxSizeMB'] $cfg['SampleIntervalSeconds']) h"
if ($s['buffer_hours'] -and [double]$s['buffer_hours'] -ge 1.5 * $cfg['ExportEveryHours']) { 'RESULT: PASS' } else { 'RESULT: FAIL' }
