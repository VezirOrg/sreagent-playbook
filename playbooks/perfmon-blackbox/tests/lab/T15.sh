#!/bin/sh
# T15 [vm1|arc1]: on the agent side, perfmon_fetch_latest.py (skill v2.1) picks the newest zip of the machine,
# checks the manifest hash, unzips, and the converter gives unparsed_paths=0, bad_cells=0, short_rows=0 and rows =
# manifest rows. Needs >= 2 zips of the machine (T09) and the skill deployed on the lab agent.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"; name=$(vm_real "$m" | tr 'A-Z' 'a-z')
newest=$(guest dc verify-blobs.ps1 -Account "$sa" -Prefix "$(prefix_of "$m")" -Last 1 -AllowIncomplete)
echo "$newest" | sed -n '1,3p'
q="Skill check, no analysis. Use your perfmon-triage skill files. In your terminal: (1) find the skill folder (find / -name perfmon_fetch_latest.py -path '*perfmon-triage*' 2>/dev/null | head -1), (2) az login --identity --allow-no-subscriptions, (3) python3 <skill folder>/perfmon_fetch_latest.py --account $sa --machine $name --out /tmp/t15, (4) python3 <skill folder>/perfmon_csv_to_sqlite.py <the csv it printed> /tmp/t15/t15.db --force. Report verbatim: every line the fetch script printed, and the converter lines rows, unparsed_paths, bad_cells, short_rows, first_ts, last_ts."
out=$(cd "$lab" && scripts/ask-agent "$q" 2>&1 | grep -v '^direnv:' | mask); echo "$out" | tail -40
zipline=$(echo "$newest" | grep '^zip ' | head -1 | sed 's/^zip //; s/:.*//; s#.*/##')
rows=$(echo "$newest" | grep 'manifest:' | head -1 | sed -E 's/.*rows ([0-9]+).*/\1/')
echo "$out" | grep -q "$(echo "$zipline" | sed "s/$name/vm1/I")" && ok "agent picked the newest zip" || bad "agent did not name the newest zip ($zipline)"
for k in unparsed_paths bad_cells short_rows; do echo "$out" | grep -Eq "$k[^0-9]*0\b" && ok "$k = 0" || bad "$k not 0"; done
echo "$out" | grep -Eq "rows[^0-9]*$rows\b" && ok "rows = manifest rows ($rows)" || bad "rows differ from the manifest ($rows)"
echo "$out" | grep -qi 'sha256: OK' && ok 'manifest hash checked' || bad 'no hash check line'
finish
