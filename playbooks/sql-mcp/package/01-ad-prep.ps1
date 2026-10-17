# Step 1. Run on a domain controller as a Domain Admin. Idempotent.
# Creates the KDS root key (once per forest) and the gMSA that runs Data API builder, retrievable only by the MCP host.
#   -McpHost <name>       computer name of the MCP host (the server that will run Data API builder)
#   -Gmsa <name>          gMSA name (default gmsa-sqlmcp)
#   -LabBackdateKdsKey    LAB ONLY: make a new KDS root key effective 10 h in the past, so step 3 can run now.
#                         Without it a new key is effective immediately but usable by gMSAs only after ~10 h.
param([Parameter(Mandatory)][string]$McpHost, [string]$Gmsa = 'gmsa-sqlmcp', [switch]$LabBackdateKdsKey)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
if (-not (Get-KdsRootKey)) {
  if ($LabBackdateKdsKey) { Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) | Out-Null }
  else { Add-KdsRootKey -EffectiveImmediately | Out-Null; 'KDS root key created: wait about 10 h before step 3 (03-dab-install.ps1).' }
}
$dns = (Get-ADDomain).DNSRoot
if (-not (Get-ADServiceAccount -Filter "Name -eq '$Gmsa'")) {
  New-ADServiceAccount -Name $Gmsa -DNSHostName "$Gmsa.$dns" -PrincipalsAllowedToRetrieveManagedPassword "$McpHost$"
}
Get-ADServiceAccount $Gmsa -Properties PrincipalsAllowedToRetrieveManagedPassword |
  Format-List Name, SamAccountName, PrincipalsAllowedToRetrieveManagedPassword
