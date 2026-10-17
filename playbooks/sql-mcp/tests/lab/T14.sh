#!/bin/sh
# T14: the live configuration (run as a copy on localhost:5001, anonymous read added to the copy only) has 7 entities
# per server with all their columns, the key columns described, and each server answers a read.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
n=$(echo $sqls | wc -w | tr -d ' ')
o=$(guest vm1 dab-copy.ps1 -Mode describe); echo "$o" | grep -E '^(VERSION|READ) '
check "copy listens" "$(echo "$o" | kv LISTENING)" "yes"
check "entities" "$(echo "$o" | kv ENTITIES)" "$((n * 7))"
check "entities with their columns" "$(echo "$o" | kv WITH_FIELDS)" "$((n * 7))"
d=$(echo "$o" | kv DESCRIBED_FIELDS); [ "${d:-0}" -ge $((n * 15)) ] && ok "described fields: $d" || bad "described fields: '$d'"
for s in $sqls; do check "read ${s}_wait_stats" "$(echo "$o" | kv "READ ${s}_wait_stats")" "ok"; done
finish
