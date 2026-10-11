#!/bin/sh
# T06 [vm1|arc1]: collector running with the template's counters (36 + G1 + G2 + present G3), binary circular,
# interval and MaxSizeMB from the policy parameters, no duration limit, the .blg growing.
. "$(dirname "$0")/common.sh"
out=$(guest "${1:-vm1}" collector.ps1); echo "$out"
echo "$out" | grep -q 'RESULT: PASS'
