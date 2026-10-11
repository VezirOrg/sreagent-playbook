#!/bin/sh
# T17 [vm1|arc1]: skill range mode (P44). The T16 plants (leak + CPU, 45 min) run across an export boundary: an extra
# export at +16 min splits the CPU burst (+10 .. +22) over two zips. The agent is asked, in a new thread, for the
# range from the load's start to its end; it must fetch both zips, list both in the Capture section, and find the
# leak and the CPU burst. Scored like T16 (score >= 80, both found, nothing invented) plus "both zips named".
#   T17.sh vm1 start    (export, start the load, then sleep until +16 min and export again: the boundary)
#   T17.sh vm1 finish   (after the load ended: export, ask the range question, score)
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"; step="${2:-finish}"; name=$(vm_real "$m" | tr 'A-Z' 'a-z')
ev="$root/files/test-runs/$(date -u +%y%m%d)-${rg#rg-}"; mkdir -p "$ev"
if [ "$step" = start ]; then
  nxt=$(v "$m" '$i = & schtasks.exe /query /tn \PerfmonBlackbox\Export /v /fo csv | ConvertFrom-Csv | Select-Object -First 1; [int](([datetime]::Parse($i."Next Run Time")) - (Get-Date)).TotalMinutes' | tr -d '\r' | tail -1)
  [ "${nxt:-0}" -gt 55 ] || { echo "a scheduled export falls inside the T17 window"; exit 1; }
  guest "$m" export-now.ps1 | tail -1
  guest "$m" make-trouble.ps1 -Start
  echo "load started; boundary export at +16 min"; sleep 960
  guest "$m" export-now.ps1 | grep -E '^last_blob|RESULT'
  echo "boundary export done; run 'T17.sh $m finish' after ~31 min"; exit 0
fi
guest "$m" make-trouble.ps1 -Status > "$ev/T17-$m-truth.raw" 2>&1
python3 -c 'import json,sys; t=json.load(open(sys.argv[1], encoding="utf-8-sig")); sys.exit(0 if t.get("ended") else 1)' "$ev/T17-$m-truth.raw" 2>/dev/null || { echo "planted load not finished yet"; exit 1; }
e=$(guest "$m" export-now.ps1); echo "$e" | tail -2
range=$(python3 -c 'import json,sys; t=json.load(open(sys.argv[1], encoding="utf-8-sig")); print(t["started"][:16] + "|" + t["ended"][:16])' "$ev/T17-$m-truth.raw")
from=${range%|*}; to=${range#*|}
zips=$(verify_blobs "$m" 3 -AllowIncomplete | grep '^zip ' | sed 's/^zip //; s/:.*//; s#.*/##; s/\.zip$//' | tr -d '\r')
echo "zips in storage (newest 3): $zips"
q="Analyse the PerfMon captures of the server $name between $from and $to (server local time) with your perfmon-triage skill. The captures are in the storage account $sa (container perfmon). Fetch what that range needs yourself and give your report."
ask_report "$q" "$ev/T17-$m-thread.raw"
python3 -c '
import sys
t = open(sys.argv[1]).read(); msgs = [x.strip() for x in t.split("--- SREAgent")[1:]]
print(max(msgs, key=len) if msgs else "")' "$ev/T17-$m-thread.raw" > "$ev/T17-$m-report.raw"
for f in thread report; do mask < "$ev/T17-$m-$f.raw" > "$ev/T17-$m-$f.txt"; rm -f "$ev/T17-$m-$f.raw"; done
mv "$ev/T17-$m-truth.raw" "$ev/T17-$m-truth.txt"
python3 -c '
import json, sys
t = json.load(open(sys.argv[1], encoding="utf-8-sig")); t["capture_first"], t["capture_last"] = sys.argv[2], sys.argv[3]
json.dump(t, open(sys.argv[1], "w"), indent=1)' "$ev/T17-$m-truth.txt" "$from:00" "$to:00"
newest=$(echo "$zips" | tail -1)
python3 -I "$pb/tests/scoring/score.py" "$ev/T17-$m-report.txt" "$ev/T17-$m-truth.txt" --zip "$newest.zip" | tee "$ev/T17-$m-score.txt"
inrange=0; named=0
for z in $zips; do
  python3 -c 'import sys,datetime as d; f=d.datetime.strptime(sys.argv[1].split("_")[-2],"%Y%m%d-%H%M%S"); t=d.datetime.strptime(sys.argv[1].split("_")[-1],"%Y%m%d-%H%M%S"); a=d.datetime.strptime(sys.argv[2],"%Y-%m-%d %H:%M"); b=d.datetime.strptime(sys.argv[3],"%Y-%m-%d %H:%M"); sys.exit(0 if t>=a and f<=b else 1)' "$z" "$from" "$to" || continue
  inrange=$((inrange + 1)); grep -q "$z" "$ev/T17-$m-report.txt" && named=$((named + 1))
done
echo "zips overlapping the range: $inrange, named in the report: $named"
[ "$inrange" -ge 2 ] && [ "$named" -eq "$inrange" ] && grep -q '> PASS' "$ev/T17-$m-score.txt"
