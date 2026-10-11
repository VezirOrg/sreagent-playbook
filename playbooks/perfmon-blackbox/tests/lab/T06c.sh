#!/bin/sh
# T06c [vm1|arc1] (run RIGHT AFTER lab-params.sh MaxSizeMB=32 has landed, from a smaller MaxSizeMB): export at once, so
# the re-create boundary is still in the rings: the boundary hole (re-create ring -> new ring) is a collector_restart
# of <= 30 s, i.e. nothing lost across the re-create (a leading buffer_overrun from before the change is allowed:
# the small ring may have wrapped while the change propagated); then the live file grows past 16 MB and stays <= 32 MB.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"; minutes="${2:-12}"
e=$(guest "$m" export-now.ps1); echo "$e" | tail -2
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb" | grep -E 'manifest:|gap |source '
w=$(guest "$m" watch-size.ps1 -Minutes "$minutes" -MinMB 17); echo "$w"
echo "$vb" | grep -q 'recreate-m16' && ok 'the re-create ring (16 MB) is in the export' || bad 'no re-create ring in the export'
lead=$(echo "$vb" | grep 'gap ' | head -1)
rest=$(echo "$vb" | grep 'gap ' | sed '1{/buffer_overrun/d;}')
if echo "$rest" | grep -v collector_restart | grep -q 'gap '; then bad 'a gap other than the re-create restart'; else ok 'no other gap'; fi
for s in $(echo "$rest" | grep collector_restart | awk '{for(i=1;i<=NF;i++) if($i=="s") print $(i-1)}'); do
  python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= 30 else 1)' "$s" && ok "re-create restart $s s <= 30 s" || bad "re-create restart $s s"; done
echo "$w" | grep -q 'collector max 32 MB' && ok 'collector max 32 MB' || bad 'collector max not 32'
echo "$w" | grep -q 'RESULT: PASS' && ok 'grew past 16 MB, never above 32 MB' || bad 'size check'
finish
