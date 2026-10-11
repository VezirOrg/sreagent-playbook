#!/bin/sh
# T18f: the whole chain works with shared key access disabled and no SAS anywhere (P45): the account really refuses
# keys (T14), storage-mode download works on arc1 (T18b) and, when switched, on vm1 (T18c), each machine uploads with its
# identity (T11), and the agent fetches with its identity (T15). Also: no lab script or shipped file uses a key or a SAS.
. "$(dirname "$0")/common.sh"
check allowSharedKeyAccess "$(az storage account show -g "$rg" -n "$sa" --query allowSharedKeyAccess -o tsv)" false
check publicNetworkAccess "$(az storage account show -g "$rg" -n "$sa" --query publicNetworkAccess -o tsv)" Disabled
hits=$(grep -rn -i -e 'account-key' -e 'generate-sas' -e 'AccountKey=' -e 'SharedAccessSignature' "$pb/package" "$pb/skill" "$pb/policy" "$pb/infra" "$pb/scripts" "$here" 2>/dev/null | grep -v 'T18f.sh' | wc -l | tr -d ' ')
check 'key or SAS use in shipped code and lab scripts' "$hits" 0
for t in "T18 arc1 storage" "T11 vm1" "T11 arc1" "T15 vm1"; do
  set -- $t
  if [ "$1" = T18 ]; then sh "$here/T18.sh" "$2" "$3" >/dev/null 2>&1; else sh "$here/$1.sh" "$2" >/dev/null 2>&1; fi && ok "$t" || bad "$t"
done
finish
