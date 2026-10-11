#!/bin/sh
# lab-infra.sh: deploy infra/main.bicep into the playbook lab (the private lab template's VNet, pe subnet and
# privatelink.blob zone; the SRE Agent's system identity and UAMI as readers). Run from the repo root:
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-infra.sh
# Prints the storage account resource ID (the policies' StorageAccountResourceId). Idempotent.
set -eu
here=$(cd "$(dirname "$0")" && pwd); pb=$(cd "$here/../.." && pwd); root=$(cd "$pb/../.." && pwd)
lab="$root/.lab/perfmon-blackbox"
rg=$(cd "$lab" && azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
sub=$(az account show --query id -o tsv)
name="stbb$(printf '%s' "$sub/$rg" | shasum | cut -c1-12)"
vnet=$(az network vnet list -g "$rg" --query "[0].name" -o tsv)
subnet=$(az network vnet subnet show -g "$rg" --vnet-name "$vnet" -n pe --query id -o tsv)
zone=$(az network private-dns zone show -g "$rg" -n "privatelink.blob.core.windows.net" --query id -o tsv)
agent_sys=$(az resource list -g "$rg" --resource-type Microsoft.App/agents --query "[0].identity.principalId" -o tsv)
uami=$(az identity list -g "$rg" --query "[0].principalId" -o tsv)
az deployment group create -g "$rg" -n perfmon-blackbox-infra -f "$pb/infra/main.bicep" \
  -p storageAccountName="$name" privateEndpointSubnetId="$subnet" blobPrivateDnsZoneId="$zone" \
  readerPrincipalIds="[\"$agent_sys\",\"$uami\"]" --query "properties.outputs.storageAccountResourceId.value" -o tsv
