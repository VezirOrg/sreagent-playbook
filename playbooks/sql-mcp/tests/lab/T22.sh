#!/bin/sh
# T22: one SQL Server unreachable at start: DAB does not start at all (by design, the README says how to see it and
# how to take the server out). On a copy on localhost:5001 whose sql2 points at a name that does not resolve: no SQL
# Server is stopped. dab.log must name an entity of the unreachable server
# ("Cannot obtain Schema for entity sql2_…"), which is how docs/operations.md finds it.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
o=$(guest vm1 dab-copy.ps1 -Mode dead -Dead sql2); echo "$o" | grep '^LOG ' | tail -5
check "copy listens" "$(echo "$o" | kv LISTENING)" "no"
check "the log names the failing server's entity" "$(echo "$o" | kv LOG_FAILED_SERVER)" "sql2"
finish
