#!/bin/sh
# lab-up.sh: build the sql-mcp lab with one command, as a rehearsal of the README's install steps (decisions S16).
# From the repo root:
#   direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh                          1. Lab build     (README steps 1-3)
#   playbooks/sql-mcp/package/admin/entra-setup.sh --agent <id>   (an admin)     2. Admin consent (README step 4)
#   direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh --connect --app-id <id>  3. MCP connect   (README steps 5-6)
# Lab build = a stand-in adopter environment (the private lab template: dc, vm1, sql1, sql2 and the SRE Agent), then
# README steps 1-3. It ends by printing the ONE Admin consent command: the lab service principal has no directory
# rights, by design (S4). `--app-id <id>` alone is an alias of `--connect --app-id <id>`. Every phase is idempotent:
# re-run it after a failure.
#   SQLMCP_LAB_TEMPLATE, SQLMCP_LAB_TAG   the private lab template (azd template and tag) for the first `azd init`;
#                                         set them in your shell (values in the private references, not in this repo)
#   SQLMCP_LAB_ENV (default lab21)        register the lab in the template's lab register BEFORE building it
set -eu
. "$(dirname "$0")/common.sh"
appid=""; connect=0
while [ $# -gt 0 ]; do
  case "$1" in
    --connect) connect=1; shift ;;
    --app-id) appid="$2"; connect=1; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ $connect -eq 0 ] || [ -n "$appid" ] || { echo "usage: lab-up.sh --connect --app-id <APP_ID>" >&2; exit 2; }

if [ $connect -eq 0 ]; then
  say "1. Lab build: $env_name (Lab ortamı + hazırlık): stand-in adopter environment + README steps 1-3"
  if [ ! -f "$lab/azure.yaml" ]; then
    : "${SQLMCP_LAB_TEMPLATE:?set SQLMCP_LAB_TEMPLATE and SQLMCP_LAB_TAG (private references)}"
    : "${SQLMCP_LAB_TAG:?set SQLMCP_LAB_TAG}"
    mkdir -p "$lab"
    (cd "$lab" && azd init -t "$SQLMCP_LAB_TEMPLATE" --branch "$SQLMCP_LAB_TAG" -e "$env_name" --no-prompt)
    git -C "$root" reset -q -- .lab 2>/dev/null || true   # azd init may stage files in the parent repo (R14)
  fi
  (cd "$lab" && { azd env select "$env_name" 2>/dev/null || azd env new "$env_name" --no-prompt; })
  (cd "$lab" && azd env set LAB_IIS_COUNT 1 && azd env set LAB_SQL_COUNT 2)
  say "the stand-in adopter environment: azd up (about 30 min)"
  start=$(date +%s)
  log="$lab/azd-up-$env_name.log"   # inside the gitignored lab folder
  if ! (cd "$lab" && azd up --no-prompt) > "$log" 2>&1; then mask < "$log" | tail -30; echo "azd up FAILED (log: $log)"; exit 1; fi
  echo "azd up took $(( ($(date +%s) - start) / 60 )) min"
  lab_load
  agent_cidr=$(agent_subnet); vm_cidr=$(subnet_of_vm vm1)
  [ -n "$agent_cidr" ] && [ -n "$vm_cidr" ] || { echo "could not read the agent or VM subnet" >&2; exit 1; }
  gmsa_login="$netbios\\gmsa-sqlmcp\$"

  say "README step 1: gMSA (on dc)"
  push_pkg dc
  run_ps dc 01-ad-prep.ps1 -McpHost "$real1" -LabBackdateKdsKey
  for s in $sqls; do
    say "README step 2: SQL login (on $s)"
    push_pkg "$s"
    v "$s" "sqlcmd -E -C -i C:\\sqlmcp\\02-sql-login.sql -v 'GmsaLogin=$gmsa_login'"
  done
  say "README step 3: Data API builder (on vm1)"
  push_pkg vm1
  run_ps vm1 03-dab-install.ps1 -From "$agent_cidr,$vm_cidr"

  say "2. Admin consent (Admin onayı): README step 4, run by an Entra admin with their own az login (idempotent):"
  echo
  echo "  playbooks/sql-mcp/package/admin/entra-setup.sh --agent $agent_id"
  echo
  echo "then 3. MCP connect: direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh --connect --app-id <APP_ID>"
  exit 0
fi

say "3. MCP connect: $env_name (MCP bağlantısı): README steps 5-6"
lab_load
echo "$appid" > "$(appid_file)"
servers=$(echo $sqls | tr ' ' ',')
say "README step 5: configuration (on vm1: $servers), start DAB"
push_pkg vm1
run_ps vm1 04-dab-config.ps1 -Servers "$servers" -Domain "$domain" -TenantId "$tenant" -AppId "$appid"
dab_restart
say "README step 6: connect the agent"
out=$(sh "$pb/package/agent/connect-agent.sh" --agent "$agent_id" --endpoint "http://$real1.$domain:5000/mcp" --app-id "$appid" 2>&1) || {
  echo "$out" | mask; echo "connect-agent FAILED"; exit 1; }
echo "$out" | mask
say "done. Next: the lab tests (playbooks/sql-mcp/tests/run.sh T11 ... T24)"
