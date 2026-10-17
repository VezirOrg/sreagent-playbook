#!/bin/sh
# lab-down.sh: tear the sql-mcp lab down, from the repo root, on the owner's word only:
#   direnv exec . playbooks/sql-mcp/tests/lab/lab-down.sh --yes
# Lists what goes, removes role assignments scoped in the lab resource group (so none is left orphaned), then
# `azd down --purge --force`. The agent's Entra role assignment goes with its identity. The Entra app itself is kept
# (reusable, no cost); an admin removes it with: package/admin/entra-setup.sh --remove
# Afterwards: run the template's lab audit and record the teardown in its lab register (same commit).
set -eu
. "$(dirname "$0")/common.sh"
[ "${1:-}" = --yes ] || { echo "usage: lab-down.sh --yes   (tears down $env_name)"; exit 2; }
lab_load
scope="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg"
say "resources in the lab resource group"
az resource list -g "$rg" --query "[].{type:type, name:name}" -o tsv | mask
say "role assignments scoped in it"
ids=$(az role assignment list --scope "$scope" --include-inherited false --query "[?starts_with(scope, '$scope')].id" -o tsv 2>/dev/null || true)
for id in $ids; do az role assignment delete --ids "$id" && echo "  deleted $(echo "$id" | mask)"; done
say "azd down (about 15 min)"
start=$(date +%s)
(cd "$lab" && azd down -e "$env_name" --purge --force) 2>&1 | mask | tail -10
echo "azd down took $(( ($(date +%s) - start) / 60 )) min"
if az group exists -n "$rg" | grep -q true; then bad "resource group still exists"; else ok "resource group gone"; fi
finish
