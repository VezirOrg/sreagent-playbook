#!/bin/sh
# T13: DAB on vm1 runs as the gMSA (task and process), version as pinned, listens on 5000, and the firewall lets in
# exactly the agent subnet and the VM subnet.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
st=$(guest vm1 host-state.ps1)
check "task user" "$(echo "$st" | kv TASK_USER)" "$netbios\\gmsa-sqlmcp\$"
check "task logon type" "$(echo "$st" | kv TASK_LOGON)" "Password"
check "process user" "$(echo "$st" | kv PROCESS_USER)" "$netbios\\gmsa-sqlmcp\$"
pin=$(sed -n "s/.*\[string\]\$Version = '\([^']*\)'.*/\1/p" "$pb/package/03-dab-install.ps1")
echo "$st" | kv DAB_VERSION | grep -q "$pin" && ok "DAB version $pin" || bad "DAB version: $(echo "$st" | kv DAB_VERSION)"
check "listens" "$(echo "$st" | kv LISTEN)" "0.0.0.0"
check "firewall rule enabled" "$(echo "$st" | kv FW_ENABLED)" "True"
check "firewall port" "$(echo "$st" | kv FW_PORT)" "5000"
want=$(printf '%s\n%s\n' "$(agent_subnet)" "$(subnet_of_vm vm1)" | sort | tr '\n' ',' | sed 's/,$//')
check "firewall remote addresses" "$(echo "$st" | kv FW_REMOTE)" "$want"
finish
