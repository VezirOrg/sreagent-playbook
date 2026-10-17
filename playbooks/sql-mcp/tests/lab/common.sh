# common.sh: shared helpers for the sql-mcp lab scripts and tests (sourced). Run them from the repo root through
# direnv (`direnv exec . playbooks/sql-mcp/tests/lab/<script>`). Never prints a secret; IDs and the real host name are
# masked in everything except the one admin command lab-up.sh prints.
#   SQLMCP_LAB_ENV   azd environment of the lab (default lab21)
#   SQLMCP_LAB_DIR   checkout of the private lab template (default <repo>/.lab/sql-mcp, gitignored, R14)
here=$(cd "$(dirname "$0")" && pwd); pb=$(cd "$here/../.." && pwd); root=$(cd "$pb/../.." && pwd)
env_name="${SQLMCP_LAB_ENV:-lab21}"
lab="${SQLMCP_LAB_DIR:-$root/.lab/sql-mcp}"
fails=0
ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1 = $2"; else bad "$1 = '$2', expected '$3'"; fi; }
finish() { if [ $fails -eq 0 ]; then return 0; else echo "  $fails check(s) failed"; return 1; fi; }
say() { echo "== $*"; }
azdv() { (cd "$lab" && azd env get-value -e "$env_name" "$1" 2>/dev/null); }
lab_load() { # the lab's facts, read from azd and ARM (never written to the repo)
  rg=$(azdv AZURE_RESOURCE_GROUP); [ -n "$rg" ] || { echo "no azd environment $env_name in $lab" >&2; return 1; }
  domain=$(azdv LAB_DOMAIN_NAME); netbios=$(azdv LAB_NETBIOS_NAME); agent_id=$(azdv SRE_AGENT_ID)
  # vm1 = the template's web member: the one VM that is neither the DC nor a SQL member
  real1=$(az vm list -g "$rg" --query "[?name!='dc' && !starts_with(name, 'sql')].name | [0]" -o tsv)
  sqls=$(az vm list -g "$rg" --query "[?starts_with(name, 'sql')].name" -o tsv | sort | tr '\n' ' ')
  tenant=$(az account show --query tenantId -o tsv)
}
mask() { # GUIDs, subscription paths and the real host name never reach the terminal or evidence files
  SQLMCP_REAL="${real1:-NOREALNAME}" perl -pe 's#/subscriptions/[0-9a-f-]{36}#/subscriptions/<sub>#g; s#[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}#<guid>#gi; s#\Q$ENV{SQLMCP_REAL}\E#vm1#gi'; }
real_of() { case "$1" in vm1) echo "$real1" ;; *) echo "$1" ;; esac; }
v() { # v <machine> '<PowerShell command>': run on a lab VM over Bastion + SSH (the default shell is Windows PowerShell 5.1)
  _vm=$(real_of "$1"); shift; (cd "$lab" && scripts/vmssh "$_vm" "$@") 2>&1 | grep -v '^direnv:' | mask; }
push_pkg() { # push_pkg <machine>: copy the package scripts to C:\sqlmcp on a lab VM
  _vm=$(real_of "$1")
  (cd "$lab" && scripts/vmssh "$_vm" 'New-Item -ItemType Directory -Force C:\sqlmcp | Out-Null' >/dev/null 2>&1)
  for _f in 01-ad-prep.ps1 02-sql-login.sql 03-dab-install.ps1 04-dab-config.ps1 tools/mcp-call.ps1; do
    (cd "$lab" && scripts/vmscp "$_vm" "$pb/package/$_f" "C:/sqlmcp/$(basename "$_f")") >/dev/null 2>&1 || bad "copy $_f to $1"
  done; }
run_ps() { # run_ps <machine> <script.ps1> [args]: run a package script under Windows PowerShell 5.1
  _m="$1"; _s="$2"; shift 2; v "$_m" "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\sqlmcp\\$_s $*"; }
subnet_of_vm() { # CIDR of the subnet of a VM's first NIC
  _nic=$(az vm show -g "$rg" -n "$(real_of "$1")" --query "networkProfile.networkInterfaces[0].id" -o tsv)
  _sn=$(az network nic show --ids "$_nic" --query "ipConfigurations[0].subnet.id" -o tsv)
  az network vnet subnet show --ids "$_sn" --query addressPrefix -o tsv; }
agent_subnet() { # CIDR of the agent's VNet-integration subnet: delegated to Microsoft.App, else the one named sreagent
  _c=$(az network vnet list -g "$rg" --query "[].subnets[?delegations[?serviceName=='Microsoft.App/environments']].addressPrefix | [] | [0]" -o tsv)
  [ -n "$_c" ] || _c=$(az network vnet list -g "$rg" --query "[].subnets[?name=='sreagent'].addressPrefix | [] | [0]" -o tsv)
  echo "$_c"; }
dab_restart() { # restart Data API builder on vm1 and wait (max 3 min) until it listens
  v vm1 "Stop-ScheduledTask DAB-sqlmcp -ErrorAction SilentlyContinue; Get-Process Microsoft.DataApiBuilder -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2; Start-ScheduledTask DAB-sqlmcp; \$i = 0; while (-not (Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue) -and \$i -lt 90) { Start-Sleep 2; \$i++ }; if (Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue) { 'DAB listening on 5000' } else { 'DAB NOT listening: tail of dab.log:'; Get-Content C:\\dab\\logs\\dab.log -Tail 30 }"; }
