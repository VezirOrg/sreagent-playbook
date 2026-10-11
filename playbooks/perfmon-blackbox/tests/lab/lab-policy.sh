#!/bin/sh
# lab-policy.sh: create the two policy definitions and assign them on the lab resource group, with the rights the
# assignment identity needs (design sec. 3.1-3.2), plus the VM prerequisites initiative; then start remediation.
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-policy.sh prereq                       # prerequisites only
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-policy.sh <contentUri> <sha256> [version] [k=v ...]
#     k=v: policy parameter overrides, e.g. MaxSizeMB=16 SampleIntervalSeconds=1 (T06b-T06e)
# ARC_VM=<Azure VM name of arc1> keeps the arc1 Azure VM out of the VM policy and the VM prerequisites (notScopes).
# Idempotent. Prints names and states only (IDs masked).
. "$(dirname "$0")/common.sh"
set -eu
loc=$(az group show -n "$rg" --query location -o tsv)
scope="/subscriptions/$sub/resourceGroups/$rg"
sa_id=$(az storage account show -g "$rg" -n "$sa" --query id -o tsv)
notscopes=""
[ -n "${ARC_VM:-}" ] && notscopes="$scope/providers/Microsoft.Compute/virtualMachines/$ARC_VM"
# dc is the lab's dev and T01 box (P24, P28): never a PerfmonBlackbox target
vmnot="$scope/providers/Microsoft.Compute/virtualMachines/dc${notscopes:+ $notscopes}"
mi_roles() { # mi_roles <principalId> <role> <scope> [condition]
  if [ -n "${4:-}" ]; then
    az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal --role "$2" --scope "$3" \
      --condition "$4" --condition-version 2.0 -o none
  else
    az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal --role "$2" --scope "$3" -o none
  fi
  echo "  role '$2' on $(echo "$3" | sed 's#.*/##')"
}

# VM prerequisites: system identity + the Machine Configuration extension (built-in initiative, looked up by name)
prereq=$(az policy set-definition list --query "[?displayName=='Deploy prerequisites to enable Guest Configuration policies on virtual machines'].name | [0]" -o tsv)
az policy assignment create -n pbb-gc-prereq --display-name 'perfmon-blackbox lab: Machine Configuration prerequisites (VMs)' \
  --policy-set-definition "$prereq" --scope "$scope" --mi-system-assigned --location "$loc" ${notscopes:+--not-scopes "$notscopes"} -o none
pp=$(az policy assignment show -n pbb-gc-prereq --scope "$scope" --query identity.principalId -o tsv)
mi_roles "$pp" Contributor "$scope"
echo "prerequisites assigned"
for ref in $(az policy set-definition show -n "$prereq" --query "policyDefinitions[].policyDefinitionReferenceId" -o tsv); do
  az policy remediation create -n "pbb-prereq-$(echo "$ref" | tr -cd 'a-zA-Z0-9' | cut -c1-40)" --policy-assignment pbb-gc-prereq \
    --definition-reference-id "$ref" -g "$rg" --resource-discovery-mode ReEvaluateCompliance -o none 2>/dev/null || true
done
[ "${1:-}" = prereq ] && exit 0

uri="${1:?contentUri}"; hash="${2:?sha256}"; ver="${3:-1.0.0}"; shift 2; [ $# -gt 0 ] && shift
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 -I "$pb/policy/build_policies.py" --content-uri "$uri" --content-hash "$hash" --version "$ver" --out "$tmp" >/dev/null
writer=$(az role definition list --custom-role-only true --scope "$scope" --query "[?roleName=='PerfMon Blackbox Writer'].id | [0]" -o tsv)
writer_guid=$(echo "$writer" | sed 's#.*/##')
params=$(python3 -c '
import json, sys
p = {"StorageAccountResourceId": sys.argv[1], "WriterRoleDefinitionId": sys.argv[2]}
for kv in sys.argv[3:]:
    k, v = kv.split("=", 1); p[k] = v
print(json.dumps({k: {"value": v} for k, v in p.items()}))' "$sa_id" "$writer" "$@")
for kind in vm arc; do
  f="$tmp/perfmon-blackbox-$kind.json"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["properties"]; [json.dump(d[k], open(sys.argv[2]+"."+k, "w")) for k in ("policyRule","parameters","metadata")]' "$f" "$f"
  az policy definition create -n "perfmon-blackbox-$kind" --display-name "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["properties"]["displayName"])' "$f")" \
    --mode Indexed --rules "$f.policyRule" --params "$f.parameters" --metadata "@$f.metadata" -o none 2>/dev/null || \
  az policy definition create -n "perfmon-blackbox-$kind" --mode Indexed --rules "$f.policyRule" --params "$f.parameters" -o none
  ns=""; [ "$kind" = vm ] && ns="$vmnot"
  az policy assignment create -n "pbb-$kind" --display-name "perfmon-blackbox lab ($kind)" --policy "perfmon-blackbox-$kind" \
    --scope "$scope" --mi-system-assigned --location "$loc" --params "$params" ${ns:+--not-scopes $ns} -o none
  pid=$(az policy assignment show -n "pbb-$kind" --scope "$scope" --query identity.principalId -o tsv)
  echo "assignment pbb-$kind"
  mi_roles "$pid" 'Guest Configuration Resource Contributor' "$scope"
  mi_roles "$pid" 'PerfMon Blackbox Deployer' "$scope"
  cond="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$writer_guid})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$writer_guid}))"
  mi_roles "$pid" 'Role Based Access Control Administrator' "$sa_id" "$cond"
done
echo "waiting 60 s for the role assignments to propagate, then remediation"
sleep 60
for kind in vm arc; do
  az policy remediation create -n "pbb-$kind-$(date -u +%H%M%S)" --policy-assignment "pbb-$kind" -g "$rg" --resource-discovery-mode ReEvaluateCompliance -o none
  echo "remediation started for pbb-$kind"
done
