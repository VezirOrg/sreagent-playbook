#!/bin/sh
# entra-setup.sh: the ADMIN step. Run by an Entra admin (Application Administrator or equivalent) with their own
# `az login`, on the tenant of the SRE Agent. Idempotent: a second run changes nothing.
#
# Creates, or reuses:
#   - the app registration <app-name> with identifier URI api://<appId> and v2 access tokens;
#   - its app role <role> (members: applications);
#   - its service principal with "assignment required" on (only assigned identities get a token);
#   - the assignment of <role> to the SRE Agent's system-assigned managed identity.
# No Azure resource is created. It prints the app ID and the tenant ID for the next steps (04-dab-config.ps1 and
# agent/connect-agent.sh).
#
#   entra-setup.sh --agent <agent-resource-id> [--app-name sql-mcp-api] [--role MCP.Read]
#   entra-setup.sh --app-name sql-mcp-api --remove     delete the app (its service principal and assignments go with it)
#
# Managed-identity tokens are cached up to ~24 h per resource: run this BEFORE the agent first asks for a token for
# api://<appId>, or its token may lack the role for a while.
set -eu
agent=""; app=sql-mcp-api; role=MCP.Read; remove=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="$2"; shift 2 ;;
    --app-name) app="$2"; shift 2 ;;
    --role) role="$2"; shift 2 ;;
    --remove) remove=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
graph=https://graph.microsoft.com/v1.0
tenant=$(az account show --query tenantId -o tsv)
appid=$(az ad app list --display-name "$app" --query "[0].appId" -o tsv)

if [ $remove -eq 1 ]; then
  if [ -z "$appid" ]; then echo "no app named $app: nothing to remove"; exit 0; fi
  az ad app delete --id "$appid"
  echo "deleted app $app ($appid); its service principal and role assignments are gone with it"
  exit 0
fi

[ -n "$agent" ] || { echo "usage: entra-setup.sh --agent <agent-resource-id> [--app-name NAME] [--role ROLE]" >&2; exit 2; }
mi=$(az resource show --ids "$agent" --api-version 2026-01-01 --query identity.principalId -o tsv)
[ -n "$mi" ] || { echo "the agent has no system-assigned identity: $agent" >&2; exit 1; }

[ -n "$appid" ] || appid=$(az ad app create --display-name "$app" --query appId -o tsv)
az ad app update --id "$appid" --identifier-uris "api://$appid"
# requestedAccessTokenVersion goes through Graph: `az ad app update --set api...` fails ("Couldn't find 'api'")
az rest -m PATCH --url "$graph/applications(appId='$appid')" --body '{"api":{"requestedAccessTokenVersion":2}}'
# reuse the role's id: a role cannot be replaced with a new id unless it is disabled first
roleid=$(az ad app show --id "$appid" --query "appRoles[?value=='$role'].id" -o tsv)
if [ -z "$roleid" ]; then
  roleid=$(uuidgen | tr 'A-Z' 'a-z')
  az rest -m PATCH --url "$graph/applications(appId='$appid')" --body "{\"appRoles\":[{\"allowedMemberTypes\":[\"Application\"],\"displayName\":\"$role\",\"description\":\"Read SQL Server DMVs through the SQL MCP server\",\"id\":\"$roleid\",\"isEnabled\":true,\"value\":\"$role\"}]}"
fi
spid=$(az ad sp list --filter "appId eq '$appid'" --query "[0].id" -o tsv)
[ -n "$spid" ] || spid=$(az ad sp create --id "$appid" --query id -o tsv)
az rest -m PATCH --url "$graph/servicePrincipals/$spid" --body '{"appRoleAssignmentRequired":true}'
if az rest -m GET --url "$graph/servicePrincipals/$spid/appRoleAssignedTo" \
     --query "value[?principalId=='$mi'].appRoleId" -o tsv | grep -qi "$roleid"; then
  echo "role $role already assigned to the agent's identity"
else
  az rest -m POST --url "$graph/servicePrincipals/$spid/appRoleAssignedTo" \
    --body "{\"principalId\":\"$mi\",\"resourceId\":\"$spid\",\"appRoleId\":\"$roleid\"}" -o none
  echo "role $role assigned to the agent's identity"
fi
# check
az rest -m GET --url "$graph/applications(appId='$appid')" --query "{uris:identifierUris, tokenVersion:api.requestedAccessTokenVersion, roles:appRoles[].value}" -o json
echo "assignment required: $(az rest -m GET --url "$graph/servicePrincipals/$spid" --query appRoleAssignmentRequired -o tsv)"
echo
echo "APP_ID=$appid"
echo "TENANT_ID=$tenant"
echo "next: 04-dab-config.ps1 -AppId <APP_ID> -TenantId <TENANT_ID> ..., then agent/connect-agent.sh --app-id <APP_ID> ..."
