#!/bin/sh
# T23: vm1 restarts (both SQL Servers up): the task starts DAB as the gMSA by itself and it listens again.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
az vm restart -g "$rg" -n "$real1" -o none && ok "vm1 restarted"
i=0; st=""
while [ $i -lt 20 ]; do
  st=$(guest vm1 host-state.ps1 2>/dev/null)
  [ "$(echo "$st" | kv LISTEN)" = "0.0.0.0" ] && break
  sleep 30; i=$((i + 1))
done
check "DAB listens after restart" "$(echo "$st" | kv LISTEN)" "0.0.0.0"
check "process user" "$(echo "$st" | kv PROCESS_USER)" "$netbios\\gmsa-sqlmcp\$"
finish
