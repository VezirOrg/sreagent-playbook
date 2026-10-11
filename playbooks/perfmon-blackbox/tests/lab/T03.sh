#!/bin/sh
# T03: one assignment of each definition on the lab RG with a system identity and exactly its roles (Guest
# Configuration Resource Contributor on the RG, PerfMon Blackbox Deployer on the RG, RBAC Administrator on the storage
# account WITH the delegation condition); dc and the arc1 Azure VM in the VM assignment's notScopes; prerequisites assigned.
. "$(dirname "$0")/common.sh"
scope="/subscriptions/$sub/resourceGroups/$rg"
sa_id=$(az storage account show -g "$rg" -n "$sa" --query id -o tsv)
for kind in vm arc; do
  j=$(az policy assignment show -n "pbb-$kind" --scope "$scope" -o json 2>/dev/null) || { bad "pbb-$kind missing"; continue; }
  pid=$(echo "$j" | python3 -c 'import json,sys; print(json.load(sys.stdin)["identity"]["principalId"])')
  [ -n "$pid" ] && ok "pbb-$kind has a system identity" || bad "pbb-$kind without identity"
  roles=$(az role assignment list --assignee "$pid" --all --query "[].[roleDefinitionName, scope, condition != null]" -o tsv 2>/dev/null | tr '\t' '|' | awk -F'|' -v sa="$sa_id" -v rg="$scope" '{ s=$2; if (s==sa) s="<storage>"; else if (s==rg) s="<rg>"; print $1" "s" "$3 }' | sort)
  exp=$(printf '%s\n' 'Guest Configuration Resource Contributor <rg> False' 'PerfMon Blackbox Deployer <rg> False' 'Reader <rg> False' 'Role Based Access Control Administrator <storage> True' | sort)
  if [ "$roles" = "$exp" ]; then ok "pbb-$kind roles exactly as designed"; else bad "pbb-$kind roles:"; echo "$roles" | mask; fi
  if [ $kind = vm ]; then
    ns=$(echo "$j" | python3 -c 'import json,sys; print(",".join(sorted(x.split("/")[-1] for x in json.load(sys.stdin).get("notScopes") or [])))')
    want=dc; az vm show -g "$rg" -n arc1 -o none 2>/dev/null && want="arc1,dc"
    check "pbb-vm notScopes" "$ns" "$want"
  fi
done
az policy assignment show -n pbb-gc-prereq --scope "$scope" -o none 2>/dev/null && ok 'VM prerequisites initiative assigned' || bad 'VM prerequisites missing'
finish
