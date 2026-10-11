#!/bin/sh
# T06b + T10b [vm1|arc1] (run after lab-params.sh MaxSizeMB=16 SampleIntervalSeconds=1 ExportEveryHours=24):
# right after an export (the ring starts empty) watch the live .blg for 15 min: it reaches 16 MB and never exceeds
# it; then export: the zip is uploaded with complete: false, a buffer_overrun gap from the last export to the oldest
# sample left (the oldest samples were overwritten: the ring wrapped), the source marked wrapped, and the newest sample
# at most 2 intervals before the export (newest present); an event-log warning exists.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
guest "$m" export-now.ps1 | tail -2
w=$(guest "$m" watch-size.ps1 -Minutes 15); echo "$w"
e=$(guest "$m" export-now.ps1); echo "$e"
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb"
ev=$(v "$m" "@(Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='PerfmonBlackbox'; Id=2002; StartTime=(Get-Date).AddMinutes(-10)} -ErrorAction SilentlyContinue).Count" | tr -d '\r' | tail -1)
echo "$w" | grep -q 'RESULT: PASS' && ok 'never above MaxSizeMB, reached it' || bad 'size check'
echo "$vb" | grep -q 'complete=False' && ok 'manifest complete: false' || bad 'manifest not incomplete'
echo "$vb" | grep -q 'buffer_overrun' && ok 'buffer_overrun gap' || bad 'no buffer_overrun gap'
echo "$vb" | grep -q 'wrapped=True' && ok 'source wrapped' || bad 'source not marked wrapped'
[ "${ev:-0}" -ge 1 ] && ok "event 2002 (incomplete export) written" || bad 'no event-log warning'
finish
