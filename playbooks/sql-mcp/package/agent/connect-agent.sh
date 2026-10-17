#!/bin/sh
# connect-agent.sh: connect the SRE Agent to the SQL MCP server over the VNet. Needs SRE Agent Administrator (or
# Contributor) on the agent; no directory rights. Idempotent.
#   1. keeps the agent's egress settings and sets "Remote MCP server access" off (allowHttpMcpServerNetworkAccess =
#      false): MCP traffic then goes through the agent's VNet, which is what reaches the MCP host;
#   2. creates or replaces the Streamable-HTTP MCP connector <name>, authenticated with the agent's system-assigned
#      managed identity (scope api://<appId>/.default) and the header X-MS-API-ROLE: <role>. No secret is stored.
#
#   connect-agent.sh --agent <agent-resource-id> --endpoint http://<host>.<domain>:5000/mcp --app-id <appId>
#                    [--role MCP.Read] [--name sqlmcp]
set -eu
agent=""; endpoint=""; appid=""; role=MCP.Read; name=sqlmcp
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="$2"; shift 2 ;;
    --endpoint) endpoint="$2"; shift 2 ;;
    --app-id) appid="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$agent" ] && [ -n "$endpoint" ] && [ -n "$appid" ] || {
  echo "usage: connect-agent.sh --agent <agent-resource-id> --endpoint <url> --app-id <appId> [--role ROLE] [--name NAME]" >&2; exit 2; }
api=2026-01-01
url="https://management.azure.com$agent"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
wait_agent() { # an agent update runs asynchronously: a connector PUT while it is InProgress is refused (OperationConflict)
  i=0
  while [ $i -lt 60 ]; do
    st=$(az rest -m GET --url "$url?api-version=$api" --query properties.provisioningState -o tsv 2>/dev/null || true)
    [ "$st" = Succeeded ] && return 0
    case "$st" in Failed|Canceled) echo "the agent is in state $st" >&2; return 1 ;; esac
    sleep 10; i=$((i + 1))
  done
  echo "the agent is still '$st' after 10 min" >&2; return 1; }

# 1. egress: send the whole egress object back (a nested PATCH may replace it), with only the one flag changed
az rest -m GET --url "$url?api-version=$api" -o json > "$tmp/agent.json"
python3 - "$tmp/agent.json" "$tmp/egress.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1]))
eg = ((a.get("properties") or {}).get("sandboxConfiguration") or {}).get("egress") or {}
if eg.get("mode") != "AzureVNet":
    sys.exit("the agent's egress mode is %r, not AzureVNet: it cannot reach a host on your network" % eg.get("mode"))
eg["allowHttpMcpServerNetworkAccess"] = False
json.dump({"properties": {"sandboxConfiguration": {"egress": eg}}}, open(sys.argv[2], "w"))
PY
wait_agent
az rest -m PATCH --url "$url?api-version=$api" --body "@$tmp/egress.json" -o none
wait_agent
echo "remote MCP server access: $(az rest -m GET --url "$url?api-version=$api" --query properties.sandboxConfiguration.egress.allowHttpMcpServerNetworkAccess -o tsv) (expected false)"

# 2. the connector (endpoint, scope and header are write-only: a GET shows them as null, which is normal)
python3 - "$tmp/connector.json" "$name" "$endpoint" "$appid" "$role" <<'PY'
import json, sys
out, name, endpoint, appid, role = sys.argv[1:]
tools = [f"{name}_{t}" for t in ("describe_entities", "read_records", "aggregate_records")]
body = {"properties": {"dataConnectorType": "Mcp", "dataSource": "placeholder", "identity": "system",
        "extendedProperties": {"type": "http", "endpoint": endpoint, "authType": "AzureARM",
                               "armScope": f"api://{appid}/.default", "X-MS-API-ROLE": role,
                               "selectedTools": tools, "toolsVisibleToMetaAgent": tools}}}
json.dump(body, open(out, "w"))
PY
az rest -m PUT --url "$url/connectors/$name?api-version=$api" --body "@$tmp/connector.json" -o none
echo "connector $name: $(az rest -m GET --url "$url/connectors/$name?api-version=$api" --query properties.provisioningState -o tsv 2>/dev/null || echo 'created')"
echo "next: ask the agent \"What is the top wait type on <server>?\" and compare with sqlcmd (README, Verify)"
