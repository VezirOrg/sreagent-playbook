#!/bin/sh
# T25: after lab-down.sh: the resource group is gone and no role assignment is scoped in it. Then run the private lab
# template's audit and record the teardown in its lab register (same commit).
. "$(dirname "$0")/common.sh"
rg=$(azdv AZURE_RESOURCE_GROUP); rg=${rg:-rg-$env_name}
check "resource group exists" "$(az group exists -n "$rg")" "false"
c=$(az role assignment list --all --query "length([?contains(scope, '/resourceGroups/$rg')])" -o tsv)
check "role assignments scoped in it" "$c" "0"
echo "  next: the template's lab audit, then its lab register entry"
finish
