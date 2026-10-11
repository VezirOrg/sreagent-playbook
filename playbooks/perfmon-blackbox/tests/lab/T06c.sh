#!/bin/sh
# T06c [vm1|arc1] (run lab-params.sh MaxSizeMB=32 SampleIntervalSeconds=1 ExportEveryHours=24 after T06b):
# the collector's max size is 32, the file grows past 16 MB and stays <= 32 MB, and no sample was lost across the
# re-create: the next export has no gap other than a collector_restart no longer than the re-create.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
w=$(guest "$m" watch-size.ps1 -Minutes 12 -MinMB 17); echo "$w"
e=$(guest "$m" export-now.ps1); echo "$e"
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb"
echo "$w" | grep -q 'collector max 32 MB' && ok 'collector max 32 MB' || bad 'collector max not 32'
echo "$w" | grep -q 'RESULT: PASS' && ok 'grew past 16 MB, never above 32 MB' || bad 'size check'
if echo "$vb" | grep 'gap ' | grep -v collector_restart | grep -q .; then bad 'a gap other than collector_restart'; else ok 'no lost samples (only collector_restart gaps, if any)'; fi
echo "$vb" | grep 'collector_restart' | awk '{for(i=1;i<=NF;i++) if($i=="s") print $(i-1)}' | while read s; do
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= 120 else 1)' "$s" && echo "  ok   restart gap $s s" || echo "  FAIL restart gap $s s > 120"; done
finish
