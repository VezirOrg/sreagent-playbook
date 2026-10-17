<#
.SYNOPSIS
  Minimal MCP client (streamable HTTP, JSON-RPC) for Windows PowerShell 5.1. No Node, no modules.
.EXAMPLE
  .\mcp-call.ps1 -List                                    # initialize + tools/list
  .\mcp-call.ps1 -Tool describe_entities
  .\mcp-call.ps1 -Tool read_records -Arguments '{"entity":"sql1_wait_stats","orderby":["wait_time_ms desc"],"first":5}'
  .\mcp-call.ps1 -Tool read_records -Arguments '...' -Token $t -Role MCP.Read   # bearer token + the app role header
.NOTES
  Never print a token. In the production shape only the SRE Agent's identity can get one (see the README).
#>
param(
  [string]$Url = 'http://localhost:5000/mcp',
  [switch]$List,
  [string]$Tool,
  [string]$Arguments = '{}',
  [string]$Token,
  [string]$Role
)
$ErrorActionPreference = 'Stop'
$script:id = 0
$script:session = $null

function Invoke-Mcp([string]$method, $params, [switch]$Notify) {
  $body = @{ jsonrpc = '2.0'; method = $method }
  if ($null -ne $params) { $body.params = $params }
  if (-not $Notify) { $script:id++; $body.id = $script:id }
  $h = @{ Accept = 'application/json, text/event-stream'; 'MCP-Protocol-Version' = '2025-06-18' }
  if ($script:session) { $h['Mcp-Session-Id'] = $script:session }
  if ($Token) { $h['Authorization'] = "Bearer $Token" }
  if ($Role) { $h['X-MS-API-ROLE'] = $Role }
  $json = $body | ConvertTo-Json -Depth 20 -Compress
  $r = Invoke-WebRequest -Uri $Url -Method Post -Headers $h -ContentType 'application/json' -UseBasicParsing `
         -Body ([Text.Encoding]::UTF8.GetBytes($json))
  if ($r.Headers['Mcp-Session-Id']) { $script:session = $r.Headers['Mcp-Session-Id'] }
  if ($Notify) { return }
  $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  if ($r.Headers['Content-Type'] -like 'text/event-stream*') {   # SSE: take the last data: line
    $text = ($text -split "`n" | Where-Object { $_ -like 'data:*' } | Select-Object -Last 1).Substring(5)
  }
  $res = $text | ConvertFrom-Json
  if ($res.error) { throw "MCP error $($res.error.code): $($res.error.message)" }
  $res.result
}

$init = Invoke-Mcp 'initialize' @{ protocolVersion = '2025-06-18'; capabilities = @{}; clientInfo = @{ name = 'mcp-call.ps1'; version = '1.0' } }
Invoke-Mcp 'notifications/initialized' $null -Notify
"server: $($init.serverInfo.name) $($init.serverInfo.version) as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
if ($List) { (Invoke-Mcp 'tools/list' @{}).tools | ForEach-Object { $_.name } }
if ($Tool) {
  $r = Invoke-Mcp 'tools/call' @{ name = $Tool; arguments = ($Arguments | ConvertFrom-Json) }
  if ($r.isError) { 'TOOL ERROR' }
  $r.content | ForEach-Object { $_.text }
}
