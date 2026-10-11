#!/bin/sh
# T07b [vm1|arc1]: buffer hours measured on the machine (after an export of >= 30 samples): >= 1.5 x ExportEveryHours.
# The 512 MB full-file confirmation at 10 s is the lab18 BbFull10 run (decisions P27).
. "$(dirname "$0")/common.sh"
out=$(guest "${1:-vm1}" capacity.ps1); echo "$out"
echo "$out" | grep -q 'RESULT: PASS'
