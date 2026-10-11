# common.sh: shared helpers for the lab stage tests (sourced). Never prints a secret; resource IDs are masked.
here=$(cd "$(dirname "$0")" && pwd); pb=$(cd "$here/../.." && pwd); root=$(cd "$pb/../.." && pwd)
lab="$root/.lab/perfmon-blackbox"
rg=$(cd "$lab" && azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null)
sub=$(az account show --query id -o tsv)
sa="stbb$(printf '%s' "$sub/$rg" | shasum | cut -c1-12)"
container=perfmon
fails=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }
check() { # check <label> <actual> <expected>
  if [ "$2" = "$3" ]; then ok "$1 = $2"; else bad "$1 = '$2', expected '$3'"; fi; }
mask() { sed -E 's#/subscriptions/[0-9a-f-]{36}#/subscriptions/<sub>#g; s#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#<guid>#g'; }
v() { (cd "$lab" && scripts/vmssh "$@") 2>&1 | grep -v '^direnv:'; }
vm_real() { # the lab's real VM name for a playbook machine name (vm1 -> the template's web member)
  case "$1" in vm1) (cd "$lab" && azd env get-value LAB_VMS 2>/dev/null) | tr ',' '\n' | grep -v '^dc$' | head -1 ;; *) echo "$1" ;; esac; }
finish() { if [ $fails -eq 0 ]; then return 0; else echo "  $fails check(s) failed"; return 1; fi; }
