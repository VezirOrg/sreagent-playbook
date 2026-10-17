#!/bin/sh
# T24: the placeholder root still works with the pinned DAB build (root has 0 entities, DAB starts, all servers'
# entities are there). On an upgrade, pass the new version and the SHA-256 of its zip: the same check runs on a copy
# with that build (localhost:5001), before the pin changes.
#   T24.sh [<version> <sha256>]
. "$(dirname "$0")/common.sh"
lab_load || exit 1
n=$(echo $sqls | wc -w | tr -d ' ')
if [ $# -ge 2 ]; then o=$(guest vm1 dab-copy.ps1 -Mode describe -Version "$1" -Sha256 "$2"); else o=$(guest vm1 dab-copy.ps1 -Mode describe); fi
echo "$o" | grep '^VERSION '
check "root entities" "$(echo "$o" | kv ROOT_ENTITIES)" "0"
check "starts with the placeholder root" "$(echo "$o" | kv LISTENING)" "yes"
check "entities" "$(echo "$o" | kv ENTITIES)" "$((n * 7))"
finish
