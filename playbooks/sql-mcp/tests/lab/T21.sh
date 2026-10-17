#!/bin/sh
# T21: a server is taken out by renaming its file to .off: DAB starts without it, silently, with the other server's 7
# entities, and still reads that server (on a copy on localhost:5001; the live files are not touched).
. "$(dirname "$0")/common.sh"
lab_load || exit 1
o=$(guest vm1 dab-copy.ps1 -Mode off -Off sql1)
check "copy listens with sql1.json.off" "$(echo "$o" | kv LISTENING)" "yes"
check "entities" "$(echo "$o" | kv ENTITIES)" "7"
check "read sql2_wait_stats" "$(echo "$o" | kv 'READ sql2_wait_stats')" "ok"
finish
