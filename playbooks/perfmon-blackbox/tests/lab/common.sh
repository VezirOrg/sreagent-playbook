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
sshuser() { if [ "$1" = arc1 ]; then echo "--user ${VM_ADMIN_USERNAME:-azureuser}"; fi; }   # arc1 is not domain-joined
v() { _vm=$(vm_real "$1"); _u=$(sshuser "$1"); shift; (cd "$lab" && scripts/vmssh $_u "$_vm" "$@") 2>&1 | grep -v '^direnv:' | mask; }
guest() { # guest <machine> <tests/lab/guest/x.ps1> [args]: run an in-guest check under Windows PowerShell 5.1 (P25)
  _vm=$(vm_real "$1"); _u=$(sshuser "$1"); _f="$here/guest/$2"; shift 2
  (cd "$lab" && scripts/vmssh $_u "$_vm" "New-Item -ItemType Directory -Force C:\\BbDev\\t | Out-Null" >/dev/null 2>&1 && scripts/vmscp $_u "$_vm" "$_f" "C:/BbDev/t/$(basename "$_f")" >/dev/null 2>&1 &&
   scripts/vmssh $_u "$_vm" "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\BbDev\\t\\$(basename "$_f") $*") 2>&1 | grep -v '^direnv:' | mask; }
machine_id() { # machine_id vm1|arc1 -> Azure resource ID (Compute VM or Arc machine)
  case "$1" in arc1) echo "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.HybridCompute/machines/arc1" ;;
    *) echo "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Compute/virtualMachines/$(vm_real "$1")" ;; esac; }
pkg_env="$lab/pbb-package.env"   # PKG_URI, PKG_SHA256, PKG_VERSION of the package under test (lab-only file)
[ -f "$pkg_env" ] && . "$pkg_env"
finish() { if [ $fails -eq 0 ]; then return 0; else echo "  $fails check(s) failed"; return 1; fi; }
prefix_of() { echo "$sub/$rg/$(vm_real "$1")" | tr 'A-Z' 'a-z'; }
verify_blobs() { # verify_blobs <machine> <last N> [extra args]: run guest/verify-blobs.ps1 on dc (the lab reader)
  _bm="$1"; _bn="$2"; shift 2
  (cd "$lab" && scripts/vmssh dc "if (-not (Test-Path C:\\\\BbDev\\\\src\\\\package)) { 'NO-SRC' }" 2>/dev/null) | grep -q NO-SRC && \
    echo "  (dc has no C:\\BbDev\\src: run tests/run.sh L05 or T01 first)"
  guest dc verify-blobs.ps1 -Account "$sa" -Prefix "$(prefix_of "$_bm")" -Last "$_bn" "$@"; }
ga_json() { # ga_json <machine>: the guest assignment plus its latest report's resources, as one JSON object
  base="https://management.azure.com$(machine_id "$1")/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox"
  a=$(az rest --method get --url "$base?api-version=2022-01-25" -o json 2>/dev/null) || { echo '{}'; return; }
  r=$(az rest --method get --url "$base/reports?api-version=2022-01-25" -o json 2>/dev/null || echo '{"value":[]}')
  python3 -c '
import json, sys
a = json.loads(sys.argv[1])["properties"]; v = json.loads(sys.argv[2]).get("value") or []
v.sort(key=lambda x: x["properties"].get("endTime") or "")
res = (v[-1]["properties"].get("details") or {}).get("resources", []) if v else []
a["resources"] = [{"id": (x.get("properties") or {}).get("ResourceId"), "status": x.get("complianceStatus"),
                   "reasons": " | ".join(y.get("phrase", "") for y in x.get("reasons") or [])} for x in res]
print(json.dumps(a))' "$a" "$r"; }
ask_report() { # ask_report "<question>" <out.raw>: ask the agent in a new thread and wait (up to 30 min) until one of its
  # messages is the report (it holds a "Capture" section), then write the whole thread (ask-agent's format) to <out.raw>
  _q="$1"; _o="$2"
  (cd "$lab" && scripts/ask-agent "$_q" > "$_o" 2> "$_o.err") || true
  _tid=$(sed -n 's/^thread //p' "$_o.err" | head -1); rm -f "$_o.err"
  [ -n "$_tid" ] || return 0
  _ep=$(az resource show -g "$rg" -n "$(cd "$lab" && azd env get-value SRE_AGENT_NAME 2>/dev/null)" --resource-type Microsoft.App/agents --api-version 2025-05-01-preview --query properties.agentEndpoint -o tsv)
  for _i in $(seq 1 60); do
    grep -qi 'capture' "$_o" && [ "$(grep -c '' "$_o")" -gt 30 ] && return 0
    sleep 30
    az rest -m GET --url "$_ep/api/v1/threads/$_tid/messages" --resource https://azuresre.dev 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin); msgs = d.get("value", d) if isinstance(d, dict) else d
for m in msgs:
    if m.get("messageType") == "Reasoning": continue
    role = (m.get("author") or {}).get("role"); text = m.get("text") or ""
    cmd = (m.get("azCliExecution") or {}).get("command")
    if text or cmd: print(f"--- {role}\n" + (text or f"az: {cmd}"))' > "$_o.new" 2>/dev/null && [ -s "$_o.new" ] && mv "$_o.new" "$_o"
  done; rm -f "$_o.new"; }
