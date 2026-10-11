#!/bin/sh
# T16 [vm1|arc1]: plant known problems (make-trouble.ps1, ~70 min), export, then ask the agent in a new thread to
# analyse the latest capture of the machine; score the report (tests/scoring/score.py): pass = >= 80 and every planted
# problem found, and the report names the latest zip. Evidence (masked) in files/test-runs/<date>-<lab>/.
#   T16.sh vm1 start   (export now so the next zip covers the trouble window, then start the planted load)
#   T16.sh vm1 finish  (after the load ended: export, ask the agent, score)
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"; step="${2:-finish}"; name=$(vm_real "$m" | tr 'A-Z' 'a-z')
ev="$root/files/test-runs/$(date -u +%y%m%d)-${rg#rg-}"; mkdir -p "$ev"
if [ "$step" = start ]; then
  # the latest zip must cover the whole planted window: refuse if the Export task's schedule fires within 80 min
  nxt=$(v "$m" '$i = & schtasks.exe /query /tn \PerfmonBlackbox\Export /v /fo csv | ConvertFrom-Csv | Select-Object -First 1; [int](([datetime]::Parse($i."Next Run Time")) - (Get-Date)).TotalMinutes' | tr -d '\r' | tail -1)
  echo "next scheduled export in ${nxt:-?} min"
  [ "${nxt:-0}" -gt 80 ] || { echo "a scheduled export falls inside the T16 window: start right after it"; exit 1; }
  v "$m" 'Get-ChildItem T:\bbio, C:\bbio -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; "cleaned leftover disk-plant files"'
  guest "$m" export-now.ps1 | tail -2
  guest "$m" make-trouble.ps1 -Start
  echo "planted load started; run 'T16.sh $m finish' after ~72 min"; exit 0
fi
guest "$m" make-trouble.ps1 -Status > "$ev/T16-$m-truth.raw" 2>&1
python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); sys.exit(0 if t.get("ended") else 1)' "$ev/T16-$m-truth.raw" 2>/dev/null || { echo "planted load not finished yet"; exit 1; }
e=$(guest "$m" export-now.ps1); echo "$e" | tail -3
zip=$(echo "$e" | tr -d '\r' | grep '^last_blob:' | sed 's/^last_blob: //; s#.*/##')
# the capture range the agent should quote is the latest zip's own window (a scheduled export may have cut the load)
win=$(verify_blobs "$m" 1 -AllowIncomplete | grep 'manifest:' | head -1)
python3 -c '
import json, re, sys
t = json.load(open(sys.argv[1], encoding="utf-8-sig"))
m = re.search(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\.\d+ \.\. (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)", sys.argv[2])
if m: t["capture_first"], t["capture_last"] = m.group(1), m.group(2)
json.dump(t, open(sys.argv[1], "w"), indent=1)' "$ev/T16-$m-truth.raw" "$win"
q="Analyse the latest PerfMon capture of the server $name with your perfmon-triage skill. The captures are in the storage account $sa (container perfmon). Fetch the latest one yourself and give your report."
(cd "$lab" && scripts/ask-agent "$q" 2>&1) | grep -v '^direnv:' > "$ev/T16-$m-thread.raw"
python3 -c '
import sys
t = open(sys.argv[1]).read()
msgs = [x.strip() for x in t.split("--- SREAgent")[1:]]
# the report is the longest agent message (the last one is often a short wrap-up)
print(max(msgs, key=len) if msgs else "")' "$ev/T16-$m-thread.raw" > "$ev/T16-$m-report.raw"
for f in thread report; do mask < "$ev/T16-$m-$f.raw" > "$ev/T16-$m-$f.txt"; rm -f "$ev/T16-$m-$f.raw"; done
mv "$ev/T16-$m-truth.raw" "$ev/T16-$m-truth.txt"   # already masked by guest()
# scored on the masked texts: the machine is 'vm1'/'arc1' in the report, the truth and the zip name alike
python3 -I "$pb/tests/scoring/score.py" "$ev/T16-$m-report.txt" "$ev/T16-$m-truth.txt" --zip "$(echo "$zip" | mask | tr 'A-Z' 'a-z')" | tee "$ev/T16-$m-score.txt"
rc=$(grep -q '> PASS' "$ev/T16-$m-score.txt" && echo 0 || echo 1)
echo "evidence: files/test-runs/$(basename "$ev")/T16-$m-*.txt (masked)"
exit $rc
