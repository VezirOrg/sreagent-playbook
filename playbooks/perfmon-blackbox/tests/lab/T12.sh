#!/bin/sh
# T12 [vm1|arc1]: a machine cannot write elsewhere, cannot read or list, can write its own prefix (control).
. "$(dirname "$0")/common.sh"
out=$(guest "${1:-vm1}" negative.ps1); echo "$out"
echo "$out" | grep -q 'RESULT: PASS'
