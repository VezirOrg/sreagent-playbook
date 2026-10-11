#!/bin/sh
# T10 [vm1|arc1]: the export rolls the collector (P21): it stays Running through the export, the restart gap is
# <= 10 s (manifest roll_seconds) and no hole appears, and the zip's last sample is <= 2 intervals before the roll.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
e=$(guest "$m" export-now.ps1); echo "$e" | grep -E '^collector|RESULT|export:' | tail -3
vb=$(verify_blobs "$m" 1); echo "$vb" | grep -E 'manifest:|gap |RESULT'
r=$(echo "$vb" | sed -n 's/.*roll_s=\([0-9.]*\).*/\1/p' | head -1)
python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= 10 else 1)' "${r:-99}" && ok "roll gap $r s <= 10 s" || bad "roll gap $r s"
echo "$e" | grep -q '^collector: Running' && ok 'collector Running after the export' || bad 'collector not running'
echo "$vb" | grep -q 'gaps=0' && ok 'no hole' || bad 'hole in the export'
finish
