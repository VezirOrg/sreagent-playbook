#!/bin/sh
# T10e [vm1]: an unreadable pending ring is reported and removed (P54 RING-A, rc.9 and later). vm1 holds a real ring
# cut by an abrupt restart. Exports keep it twice ("failed read 1 of 3", "2 of 3"); the third failed read deletes it,
# writes event 2003, and that run's manifest carries an unreadable_ring gap (complete: false). A scheduled export may
# already have counted read 1 (first T10e run, 2026-10-12), so the test exports until the ring is gone (at most 3),
# reads the whole log tail for the file, and checks the last 3 manifests.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
log='C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log'
bad1=$(v "$m" "Get-Content $log -Tail 400 | Select-String 'unreadable pending buffers kept' | Select-Object -Last 1 | % { \$_.Line }" | tr -d '\r' | sed 's/.*kept for the next run: //')
echo "unreadable before: ${bad1:-none}"
[ -n "$bad1" ] || { bad 'no unreadable ring on the machine (nothing to test)'; finish; exit 1; }
for n in 1 2 3; do guest "$m" export-now.ps1 | grep -E '^(export task|state:|RESULT)'
  v "$m" "Get-Content $log -Tail 20" | grep -q 'failed read 3 of 3, deleted' && break; done
l=$(v "$m" "Get-Content $log -Tail 400" | tr -d '\r' | grep 'unreadable')
echo "$l"
ev=$(v "$m" "Get-EventLog -LogName Application -Source PerfmonBlackbox -After (Get-Date).AddHours(-1) | ? { \$_.EventID -eq 2003 } | % { \$_.Message }" | tr -d '\r')
echo "$ev"
mf=$(verify_blobs "$m" 3 -AllowIncomplete); echo "$mf" | grep -E 'manifest:|gap|RESULT'
for f in $bad1; do f=${f%,}
  echo "$l" | grep -q "$f: failed read 1 of 3" && echo "$l" | grep -q "$f: failed read 2 of 3" && ok "$f kept twice" || bad "$f not kept twice"
  echo "$l" | grep -q "$f .*failed read 3 of 3, deleted" && ok "$f deleted on the third read" || bad "$f not deleted"
  echo "$ev" | grep -q "$f" && ok "event 2003 for $f" || bad "no event 2003 for $f"
  echo "$mf" | grep -q "unreadable_ring" && ok "manifest: unreadable_ring gap" || bad "no unreadable_ring gap in the last 3 manifests"
done
finish
