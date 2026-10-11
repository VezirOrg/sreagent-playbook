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
vm_real() { # the lab's real VM name for a playbook machine name (vm1 = the template's web member); never printed
  case "$1" in vm1) az vm list -g "$rg" --query "[?name!='dc' && name!='arc1'].name | [0]" -o tsv ;; *) echo "$1" ;; esac; }
real1=$(vm_real vm1)
mask() { # IDs, GUIDs and the real VM name never reach the terminal or evidence files
  BB_REAL="${real1:-NOREALNAME}" perl -pe 's#/subscriptions/[0-9a-f-]{36}#/subscriptions/<sub>#g; s#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#<guid>#g; s#\Q$ENV{BB_REAL}\E#vm1#gi'; }
v() { m=$(vm_real "$1"); shift; (cd "$lab" && scripts/vmssh "$m" "$@") 2>&1 | grep -v '^direnv:' | mask; }
guest() { # guest <machine> <tests/lab/guest/x.ps1> [args]: run an in-guest check under Windows PowerShell 5.1 (P25)
  m=$(vm_real "$1"); f="$here/guest/$2"; shift 2
  (cd "$lab" && scripts/vmssh "$m" "New-Item -ItemType Directory -Force C:\\BbDev\\t | Out-Null" >/dev/null 2>&1 && scripts/vmscp "$m" "$f" "C:/BbDev/t/$(basename "$f")" >/dev/null 2>&1 &&
   scripts/vmssh "$m" "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\BbDev\\t\\$(basename "$f") $*") 2>&1 | grep -v '^direnv:' | mask; }
machine_id() { # machine_id vm1|arc1 -> Azure resource ID (Compute VM or Arc machine)
  case "$1" in arc1) echo "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/arc1" ;;
    *) echo "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$(vm_real "$1")" ;; esac; }
pkg_env="$lab/pbb-package.env"   # PKG_URI, PKG_SHA256, PKG_VERSION of the package under test (lab-only file)
[ -f "$pkg_env" ] && . "$pkg_env"
finish() { if [ $fails -eq 0 ]; then return 0; else echo "  $fails check(s) failed"; return 1; fi; }
prefix_of() { echo "$sub/$rg/$(vm_real "$1")" | tr 'A-Z' 'a-z'; }
verify_blobs() { # verify_blobs <machine> <last N> [extra args]: run guest/verify-blobs.ps1 on dc (the lab reader)
  m="$1"; n="$2"; shift 2
  (cd "$lab" && scripts/vmssh dc "if (-not (Test-Path C:\\\\BbDev\\\\src\\\\package)) { 'NO-SRC' }" 2>/dev/null) | grep -q NO-SRC && \
    echo "  (dc has no C:\\BbDev\\src: run tests/run.sh L05 or T01 first)"
  guest dc verify-blobs.ps1 -Account "$sa" -Prefix "$(prefix_of "$m")" -Last "$n" "$@"; }
