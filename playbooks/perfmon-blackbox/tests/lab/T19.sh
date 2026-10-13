#!/bin/sh
# T19 [vm1|arc1] (P62): the Roll task closes a piece into pending\ every 15 min; the next export relogs every piece into
# ONE zip with one CSV (sources[] lists the pieces), no gap beyond a named export_roll, no overlap; the pieces are gone
# after the upload. Waits for 3 scheduled rolls after its start (up to 50 min), so start it right after a 4-hourly export.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
t0=$(date -u +%s)
for i in $(seq 1 50); do
  n=$(v "$m" "@(Get-ChildItem C:\\ProgramData\\PerfmonBlackbox\\pending -Filter *-roll*.blg | Where-Object { \$_.LastWriteTimeUtc -gt [DateTimeOffset]::FromUnixTimeSeconds($t0).UtcDateTime }).Count" | tr -d '\r' | tail -1)
  echo "  $(date -u +%H:%MZ) roll pieces since start: $n"
  [ "${n:-0}" -ge 3 ] && break
  sleep 60
done
[ "${n:-0}" -ge 3 ] && ok "3 roll pieces in pending\\ within $(( ($(date -u +%s) - t0) / 60 )) min" || bad "only ${n:-0} roll pieces after 50 min"
v "$m" "Get-ChildItem C:\\ProgramData\\PerfmonBlackbox\\pending -Filter *.blg | ForEach-Object { '  pending ' + \$_.Name + ' ' + \$_.Length + ' created ' + \$_.CreationTime.ToString('HH:mm:ss') + ' written ' + \$_.LastWriteTime.ToString('HH:mm:ss') }"
e=$(guest "$m" export-now.ps1); echo "$e"
echo "$e" | grep -q 'RESULT: PASS' && ok 'export task result 0' || bad 'export task'
echo "$e" | grep -q 'pending: 0;' && ok 'pending\ empty after the upload' || bad 'pieces left in pending\'
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb"
echo "$vb" | grep -q 'RESULT: PASS' && ok 'blob, hashes, manifest, window' || bad 'verify-blobs'
src=$(echo "$vb" | grep -c '^  source .*-roll')
[ "$src" -ge 3 ] && ok "one zip holds $src roll pieces" || bad "zip holds $src roll pieces, expected >= 3"
echo "$vb" | grep '^  gap ' | grep -v -e export_roll -e machine_off | grep -q . && bad 'unexpected gap' || ok 'no gap beyond export_roll'
finish
