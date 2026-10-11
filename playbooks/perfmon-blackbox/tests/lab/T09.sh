#!/bin/sh
# T09 [vm1|arc1]: two exports with ~2 min in between: each zip = one CSV + manifest, PDH header, the 36 counters,
# rows = window / interval (+-1 %), manifest hash = CSV hash; export 2 starts exactly one interval after export 1
# (no gap) and repeats no sample (no overlap). Also T10 (collector running through the export, roll gap in the
# manifest) and T11 (blob path, Content-MD5 and sha256 metadata, machine identity) from the same evidence.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
o1=$(guest "$m" export-now.ps1); echo "$o1"
echo "  waiting 120 s (the collector keeps sampling)"; sleep 120
o2=$(guest "$m" export-now.ps1); echo "$o2"
o3=$(verify_blobs "$m" 2); echo "$o3"
echo "$o1$o2" | grep -c 'RESULT: PASS' | grep -q 2 && echo "$o3" | grep -q 'RESULT: PASS'
