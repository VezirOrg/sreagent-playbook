#!/bin/sh
# T15: the agent side as connect-agent.sh left it (the lab SP may do this): remote MCP access off, the connector is an
# HTTP MCP connector on the agent's system identity, and a second connect-agent.sh run succeeds. The Entra half is
# checked by the admin: entra-setup.sh run a second time must print "already assigned" (record it in docs/tests.md).
. "$(dirname "$0")/common.sh"
lab_load || exit 1
a=$(app_id); [ -n "$a" ] || { bad "no app ID (run lab-up.sh --app-id first)"; finish; exit 1; }
u="https://management.azure.com$agent_id/connectors/sqlmcp?api-version=2026-01-01"
check "connector identity" "$(az rest -m GET --url "$u" --query properties.identity -o tsv)" "system"
check "connector type" "$(az rest -m GET --url "$u" --query properties.extendedProperties.type -o tsv)" "http"
o=$(sh "$pb/package/agent/connect-agent.sh" --agent "$agent_id" --endpoint "http://$real1.$domain:5000/mcp" --app-id "$a" 2>&1 | mask)
echo "$o" | grep -q 'remote MCP server access: false' && ok "connect-agent rerun: remote MCP access off" || bad "connect-agent rerun: $o"
echo "$o" | grep -q 'connector sqlmcp' && ok "connect-agent rerun: connector PUT" || bad "connector PUT failed (lab SP rights? ask the vezir)"
finish
