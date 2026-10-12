#!/bin/sh
# lab-policy.sh: create the two policy definitions and assign them on the lab resource group, with the rights the
# assignment identity needs (design sec. 3.1-3.2), plus the VM prerequisites initiative; then start remediation.
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-policy.sh prereq                       # prerequisites only
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-policy.sh <contentUri> <sha256> [version] [k=v ...]
#     k=v: policy parameter overrides, e.g. MaxSizeMB=16 SampleIntervalSeconds=1 (T06b-T06e)
#     PackageContainerResourceId=<container ID>: storage mode (P48): definitions perfmon-blackbox-<kind>-storage and
#       assignments pbb-<kind>-storage; without it GitHub mode (perfmon-blackbox-<kind>, pbb-<kind>). The other mode's
#       assignment of the same kind is removed first, with its identity's role assignments (P48: never both modes over
#       one machine; switch = unassign, assign, remediate).
# ARC_VM=<Azure VM name of arc1> keeps the arc1 Azure VM out of the VM policy and the VM prerequisites (notScopes).
# DEFS_ONLY=1: update the definitions only (no assignment change, no role, no remediation; T18d/e, P56).
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
    # create returns an existing assignment unchanged, with its old condition (P47): update it in place
    ra=$(az role assignment list --assignee-object-id "$1" --role "$2" --scope "$3" --query "[0]" -o json)
    if [ "$(echo "$ra" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("condition") or "")')" != "$4" ]; then
      f=$(mktemp); echo "$ra" | COND="$4" python3 -c 'import json,os,sys; d=json.load(sys.stdin); d["condition"]=os.environ["COND"]; d["conditionVersion"]="2.0"; print(json.dumps(d))' > "$f"
      az role assignment update --role-assignment "@$f" -o none; rm -f "$f"
      echo "  (condition of '$2' updated)"
    fi
  else
    az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal --role "$2" --scope "$3" -o none
  fi
  echo "  role '$2' on $(echo "$3" | sed 's#.*/##')"
}

if [ -z "${DEFS_ONLY:-}" ]; then
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
fi
[ "${1:-}" = prereq ] && exit 0

uri="${1:?contentUri}"; hash="${2:?sha256}"; ver="${3:-1.0.0}"; shift 2; [ $# -gt 0 ] && shift
pkg=""; rest=""
for a in "$@"; do case "$a" in PackageContainerResourceId=*) pkg="${a#*=}" ;; *) rest="$rest $a" ;; esac; done
set -- $rest
sfx=""; other="-storage"; [ -n "$pkg" ] && { sfx="-storage"; other=""; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
python3 -I "$pb/policy/build_policies.py" --content-uri "$uri" --content-hash "$hash" --version "$ver" --out "$tmp" \
  ${pkg:+--package-container-id "$pkg"} >/dev/null
writer=$(az role definition list --custom-role-only true --scope "$scope" --query "[?roleName=='PerfMon Blackbox Writer'].id | [0]" -o tsv)
writer_guid=$(echo "$writer" | sed 's#.*/##')
params=$(python3 -c '
import json, sys
p = {"StorageAccountResourceId": sys.argv[1], "WriterRoleDefinitionId": sys.argv[2]}
for kv in sys.argv[3:]:
    k, v = kv.split("=", 1); p[k] = v
print(json.dumps({k: {"value": v} for k, v in p.items()}))' "$sa_id" "$writer" "$@")
for kind in ${KINDS:-vm arc}; do
  # P48: unassign the other mode first (its identity's role assignments too, so none are left orphaned)
  if [ -z "${DEFS_ONLY:-}" ] && old=$(az policy assignment show -n "pbb-$kind$other" --scope "$scope" --query identity.principalId -o tsv 2>/dev/null) && [ -n "$old" ]; then
    for ra in $(az role assignment list --assignee-object-id "$old" --all --query "[].id" -o tsv); do az role assignment delete --ids "$ra" -o none; done
    az policy assignment delete -n "pbb-$kind$other" --scope "$scope" -o none
    echo "removed assignment pbb-$kind$other (other mode) and its role assignments"
  fi
  f="$tmp/perfmon-blackbox-$kind$sfx.json"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["properties"]; [json.dump(d[k], open(sys.argv[2]+"."+k, "w")) for k in ("policyRule","parameters","metadata")]' "$f" "$f"
  az policy definition create -n "perfmon-blackbox-$kind$sfx" --display-name "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["properties"]["displayName"])' "$f")" \
    --mode Indexed --rules "$f.policyRule" --params "$f.parameters" --metadata "@$f.metadata" -o none 2>/dev/null || \
  az policy definition create -n "perfmon-blackbox-$kind$sfx" --mode Indexed --rules "$f.policyRule" --params "$f.parameters" -o none
  [ -n "${DEFS_ONLY:-}" ] && { echo "definition perfmon-blackbox-$kind$sfx updated (DEFS_ONLY)"; continue; }
  ns=""; [ "$kind" = vm ] && ns="$vmnot"
  az policy assignment create -n "pbb-$kind$sfx" --display-name "perfmon-blackbox lab ($kind$sfx)" --policy "perfmon-blackbox-$kind$sfx" \
    --scope "$scope" --mi-system-assigned --location "$loc" --params "$params" ${ns:+--not-scopes $ns} -o none
  pid=$(az policy assignment show -n "pbb-$kind$sfx" --scope "$scope" --query identity.principalId -o tsv)
  echo "assignment pbb-$kind$sfx"
  mi_roles "$pid" 'Guest Configuration Resource Contributor' "$scope"
  mi_roles "$pid" Reader "$scope"
  mi_roles "$pid" 'PerfMon Blackbox Deployer' "$scope"
  cond="((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$writer_guid, 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$writer_guid, 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1}))"
  # the delegation also allows the built-in Storage Blob Data Reader (2a2b9908-…): storage mode grants it on the package
  # container (P45)
  mi_roles "$pid" 'Role Based Access Control Administrator' "$sa_id" "$cond"
done
[ -n "${DEFS_ONLY:-}" ] && exit 0
echo "waiting 60 s for the role assignments to propagate, then a compliance scan (P55), then remediation"
sleep 60
az policy state trigger-scan -g "$rg" -o none   # blocks until done: the engine sees the new definitions before the remediation
for kind in ${KINDS:-vm arc}; do
  az policy remediation create -n "pbb-$kind$sfx-$(date -u +%H%M%S)" --policy-assignment "pbb-$kind$sfx" -g "$rg" --resource-discovery-mode "${REMEDIATION_MODE:-ReEvaluateCompliance}" -o none
  echo "remediation started for pbb-$kind$sfx"
done
