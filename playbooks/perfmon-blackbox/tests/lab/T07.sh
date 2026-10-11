#!/bin/sh
# T07 [vm1|arc1]: every scheduled task exists with the right trigger and principal, runs on demand with result 0.
. "$(dirname "$0")/common.sh"
out=$(guest "${1:-vm1}" tasks.ps1); echo "$out"
echo "$out" | grep -q 'RESULT: PASS'
