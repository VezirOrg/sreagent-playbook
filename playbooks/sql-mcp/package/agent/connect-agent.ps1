<#
.SYNOPSIS
  Connect the SRE Agent to the SQL MCP server over the VNet (PowerShell version of connect-agent.sh). Needs SRE Agent
  Administrator (or Contributor) on the agent; no directory rights. Idempotent.
.DESCRIPTION
  1. Keeps the agent's egress settings and sets "Remote MCP server access" off (allowHttpMcpServerNetworkAccess = false).
  2. Creates or replaces the Streamable-HTTP MCP connector, authenticated with the agent's system-assigned managed
     identity (scope api://<appId>/.default) and the header X-MS-API-ROLE. No secret is stored.
.EXAMPLE
  .\connect-agent.ps1 -Agent <agent-resource-id> -Endpoint http://vm1.contoso.local:5000/mcp -AppId <appId>
#>
param([Parameter(Mandatory)][string]$Agent, [Parameter(Mandatory)][string]$Endpoint, [Parameter(Mandatory)][string]$AppId,
      [string]$Role = 'MCP.Read', [string]$Name = 'sqlmcp')
$ErrorActionPreference = 'Stop'
$api = '2026-01-01'
$url = "https://management.azure.com$Agent"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('connect-agent-' + [guid]::NewGuid().Guid)
New-Item -ItemType Directory -Force $tmp | Out-Null
function Wait-Agent {   # an agent update runs asynchronously: a connector PUT while it is InProgress is refused (OperationConflict)
  for ($i = 0; $i -lt 60; $i++) {
    $st = az rest -m GET --url "${url}?api-version=$api" --query properties.provisioningState -o tsv
    if ($st -eq 'Succeeded') { return }
    if ($st -in 'Failed', 'Canceled') { throw "the agent is in state $st" }
    Start-Sleep 10
  }
  throw "the agent is still '$st' after 10 min"
}
try {
  Wait-Agent
  # 1. egress: send the whole egress object back, with only the one flag changed
  $a = az rest -m GET --url "${url}?api-version=$api" -o json | Out-String | ConvertFrom-Json
  $eg = $a.properties.sandboxConfiguration.egress
  if ($eg.mode -ne 'AzureVNet') { throw "the agent's egress mode is '$($eg.mode)', not AzureVNet: it cannot reach a host on your network" }
  $eg | Add-Member -NotePropertyName allowHttpMcpServerNetworkAccess -NotePropertyValue $false -Force
  @{ properties = @{ sandboxConfiguration = @{ egress = $eg } } } | ConvertTo-Json -Depth 10 -Compress | Out-File -Encoding ascii "$tmp\egress.json"
  az rest -m PATCH --url "${url}?api-version=$api" --body "@$tmp\egress.json" -o none
  Wait-Agent
  "remote MCP server access: $(az rest -m GET --url "${url}?api-version=$api" --query properties.sandboxConfiguration.egress.allowHttpMcpServerNetworkAccess -o tsv) (expected false)"
  # 2. the connector (endpoint, scope and header are write-only: a GET shows them as null, which is normal)
  $tools = @('describe_entities', 'read_records', 'aggregate_records' | ForEach-Object { "${Name}_$_" })
  @{ properties = @{ dataConnectorType = 'Mcp'; dataSource = 'placeholder'; identity = 'system'
      extendedProperties = @{ type = 'http'; endpoint = $Endpoint; authType = 'AzureARM'; armScope = "api://$AppId/.default"
        'X-MS-API-ROLE' = $Role; selectedTools = $tools; toolsVisibleToMetaAgent = $tools } } } |
    ConvertTo-Json -Depth 10 -Compress | Out-File -Encoding ascii "$tmp\connector.json"
  az rest -m PUT --url "$url/connectors/${Name}?api-version=$api" --body "@$tmp\connector.json" -o none
  "connector ${Name}: $(az rest -m GET --url "$url/connectors/${Name}?api-version=$api" --query properties.provisioningState -o tsv)"
  'next: ask the agent "What is the top wait type on <server>?" and compare with sqlcmd (README, Verify)'
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
