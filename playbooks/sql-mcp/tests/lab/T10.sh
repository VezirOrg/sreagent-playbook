#!/bin/sh
# T10: the lab is built by lab-up.sh alone (phases A and B; the only hand step is the admin's entra-setup): the four
# VMs run, the agent egresses through the VNet with remote MCP access off, DAB listens on vm1, the connector exists.
# (The build time is printed by lab-up.sh and recorded in docs/tests.md.)
. "$(dirname "$0")/common.sh"
lab_load || exit 1
for m in dc vm1 $sqls; do
  check "$m power state" "$(az vm get-instance-view -g "$rg" -n "$(real_of "$m")" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus | [0]" -o tsv)" "VM running"
done
check "SQL members" "$(echo $sqls)" "sql1 sql2"
eg=$(az rest -m GET --url "https://management.azure.com$agent_id?api-version=2026-01-01" --query "properties.sandboxConfiguration.egress.[mode, to_string(allowHttpMcpServerNetworkAccess)]" -o tsv | tr '\t\n' '  ')
check "agent egress, remote MCP access" "$(echo $eg)" "AzureVNet false"
check "connector sqlmcp" "$(az rest -m GET --url "https://management.azure.com$agent_id/connectors/sqlmcp?api-version=2026-01-01" --query properties.dataConnectorType -o tsv 2>/dev/null)" "Mcp"
st=$(guest vm1 host-state.ps1)
check "DAB task" "$(echo "$st" | kv TASK_STATE)" "Running"
check "DAB listens" "$(echo "$st" | kv LISTEN)" "0.0.0.0"
[ -n "$(app_id)" ] && ok "app ID recorded by phase B" || bad "no app ID file: run lab-up.sh --app-id <id>"
finish
