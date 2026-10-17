#!/bin/sh
# T18 (V3): the role header matters: with the connector PUT WITHOUT X-MS-API-ROLE the agent's calls get no entities
# (NoEntitiesConfigured); the connector is then put back with connect-agent.sh and checked again.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
a=$(app_id); [ -n "$a" ] || { bad "no app ID"; finish; exit 1; }
u="https://management.azure.com$agent_id/connectors/sqlmcp?api-version=2026-01-01"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/c.json" "http://$real1.$domain:5000/mcp" "$a" <<'PY'
import json, sys
out, endpoint, appid = sys.argv[1:]
tools = [f"sqlmcp_{t}" for t in ("describe_entities", "read_records", "aggregate_records")]
json.dump({"properties": {"dataConnectorType": "Mcp", "dataSource": "placeholder", "identity": "system",
           "extendedProperties": {"type": "http", "endpoint": endpoint, "authType": "AzureARM",
                                  "armScope": f"api://{appid}/.default", "selectedTools": tools,
                                  "toolsVisibleToMetaAgent": tools}}}, open(out, "w"))
PY
az rest -m PUT --url "$u" --body "@$tmp/c.json" -o none && ok "connector PUT without the role header"
o=$(ask "Use the sqlmcp describe_entities tool and tell me exactly what it returns (the error text if any)." | evidence T18-noheader)
echo "$o" | grep -qi 'NoEntitiesConfigured\|no entities' && ok "no header: no entities" || bad "no header: entities still visible"
sh "$pb/package/agent/connect-agent.sh" --agent "$agent_id" --endpoint "http://$real1.$domain:5000/mcp" --app-id "$a" 2>&1 | mask | grep -q 'connector sqlmcp' && ok "connector put back" || bad "connector NOT put back: run connect-agent.sh by hand"
o=$(ask "Use the sqlmcp describe_entities tool: how many entities are there? Answer with the number." | evidence T18-back)
echo "$o" | grep -q '14' && ok "header back: 14 entities" || bad "header back: no 14 in the answer"
finish
