<#
.SYNOPSIS
  The ADMIN step (PowerShell version of entra-setup.sh). Run by an Entra admin (Application Administrator or
  equivalent) with their own `az login`, on the tenant of the SRE Agent. Idempotent: a second run changes nothing.
.DESCRIPTION
  Creates, or reuses: the app registration (identifier URI api://<appId>, v2 access tokens), its app role (members:
  applications), its service principal with "assignment required" on, and the assignment of the role to the SRE
  Agent's system-assigned managed identity. No Azure resource is created. Prints the app ID and the tenant ID.
  Run it BEFORE the agent first asks for a token for api://<appId> (managed-identity tokens are cached up to ~24 h).
.EXAMPLE
  .\entra-setup.ps1 -Agent /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/agents/<agent>
  .\entra-setup.ps1 -AppName sql-mcp-api -Remove
#>
param([string]$Agent, [string]$AppName = 'sql-mcp-api', [string]$Role = 'MCP.Read', [switch]$Remove)
$ErrorActionPreference = 'Stop'
$graph = 'https://graph.microsoft.com/v1.0'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('entra-setup-' + [guid]::NewGuid().Guid)
New-Item -ItemType Directory -Force $tmp | Out-Null
function Body($obj) { $f = Join-Path $tmp ([guid]::NewGuid().Guid + '.json'); $obj | ConvertTo-Json -Depth 6 -Compress | Out-File -Encoding ascii $f; "@$f" }
try {
  $tenant = az account show --query tenantId -o tsv
  $appId = az ad app list --display-name $AppName --query "[0].appId" -o tsv
  if ($Remove) {
    if (-not $appId) { "no app named ${AppName}: nothing to remove"; return }
    az ad app delete --id $appId
    "deleted app $AppName ($appId); its service principal and role assignments are gone with it"
    return
  }
  if (-not $Agent) { throw 'usage: entra-setup.ps1 -Agent <agent-resource-id> [-AppName NAME] [-Role ROLE]' }
  $mi = az resource show --ids $Agent --api-version 2026-01-01 --query identity.principalId -o tsv
  if (-not $mi) { throw "the agent has no system-assigned identity: $Agent" }
  if (-not $appId) { $appId = az ad app create --display-name $AppName --query appId -o tsv }
  az ad app update --id $appId --identifier-uris "api://$appId"
  az rest -m PATCH --url "$graph/applications(appId='$appId')" --body (Body @{ api = @{ requestedAccessTokenVersion = 2 } })
  $roleId = az ad app show --id $appId --query "appRoles[?value=='$Role'].id" -o tsv
  if (-not $roleId) {
    $roleId = [guid]::NewGuid().Guid
    az rest -m PATCH --url "$graph/applications(appId='$appId')" --body (Body @{ appRoles = @(@{
          allowedMemberTypes = @('Application'); displayName = $Role; description = 'Read SQL Server DMVs through the SQL MCP server'
          id = $roleId; isEnabled = $true; value = $Role }) })
  }
  $spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv
  if (-not $spId) { $spId = az ad sp create --id $appId --query id -o tsv }
  az rest -m PATCH --url "$graph/servicePrincipals/$spId" --body (Body @{ appRoleAssignmentRequired = $true })
  $have = @(az rest -m GET --url "$graph/servicePrincipals/$spId/appRoleAssignedTo" --query "value[?principalId=='$mi'].appRoleId" -o tsv)
  if ($have -contains $roleId) { "role $Role already assigned to the agent's identity" }
  else {
    az rest -m POST --url "$graph/servicePrincipals/$spId/appRoleAssignedTo" --body (Body @{ principalId = $mi; resourceId = $spId; appRoleId = $roleId }) -o none
    "role $Role assigned to the agent's identity"
  }
  az rest -m GET --url "$graph/applications(appId='$appId')" --query "{uris:identifierUris, tokenVersion:api.requestedAccessTokenVersion, roles:appRoles[].value}" -o json
  "assignment required: $(az rest -m GET --url "$graph/servicePrincipals/$spId" --query appRoleAssignmentRequired -o tsv)"
  ''
  "APP_ID=$appId"
  "TENANT_ID=$tenant"
  'next: 04-dab-config.ps1 -AppId <APP_ID> -TenantId <TENANT_ID> ..., then agent\connect-agent.ps1 -AppId <APP_ID> ...'
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
