#!/bin/sh
# lab-up.sh: build the sql-mcp lab with one command, from the repo root:
#   direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh                 phase A: lab + AD + SQL + Data API builder
#   direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh --app-id <id>   phase B: after the admin step
# Phase A ends by printing ONE command for an Entra admin (package/admin/entra-setup.sh): the lab service principal
# has no directory rights, by design (decisions S4). Every step is idempotent: re-run either phase after a failure.
#   SQLMCP_LAB_TEMPLATE, SQLMCP_LAB_TAG   the private lab template (azd template and tag) for the first `azd init`;
#                                         set them in your shell (values in the private references, not in this repo)
#   SQLMCP_LAB_ENV (default lab21)        register the lab in the template's lab register BEFORE building it
set -eu
. "$(dirname "$0")/common.sh"
appid=""
while [ $# -gt 0 ]; do
  case "$1" in --app-id) appid="$2"; shift 2 ;; *) echo "unknown argument: $1" >&2; exit 2 ;; esac
done

if [ -z "$appid" ]; then
  say "phase A: $env_name"
  if [ ! -f "$lab/azure.yaml" ]; then
    : "${SQLMCP_LAB_TEMPLATE:?set SQLMCP_LAB_TEMPLATE and SQLMCP_LAB_TAG (private references)}"
    : "${SQLMCP_LAB_TAG:?set SQLMCP_LAB_TAG}"
    mkdir -p "$lab"
    (cd "$lab" && azd init -t "$SQLMCP_LAB_TEMPLATE" --branch "$SQLMCP_LAB_TAG" -e "$env_name" --no-prompt)
    git -C "$root" reset -q -- .lab 2>/dev/null || true   # azd init may stage files in the parent repo (R14)
  fi
  (cd "$lab" && { azd env select "$env_name" 2>/dev/null || azd env new "$env_name" --no-prompt; })
  (cd "$lab" && azd env set LAB_IIS_COUNT 1 && azd env set LAB_SQL_COUNT 2)
  say "azd up (about 30 min)"
  start=$(date +%s)
  log="$lab/azd-up-$env_name.log"   # inside the gitignored lab folder
  if ! (cd "$lab" && azd up --no-prompt) > "$log" 2>&1; then mask < "$log" | tail -30; echo "azd up FAILED (log: $log)"; exit 1; fi
  echo "azd up took $(( ($(date +%s) - start) / 60 )) min"
  lab_load
  agent_cidr=$(agent_subnet); vm_cidr=$(subnet_of_vm vm1)
  [ -n "$agent_cidr" ] && [ -n "$vm_cidr" ] || { echo "could not read the agent or VM subnet" >&2; exit 1; }
  gmsa_login="$netbios\\gmsa-sqlmcp\$"

  say "step 1: gMSA on dc"
  push_pkg dc
  run_ps dc 01-ad-prep.ps1 -McpHost "$real1" -LabBackdateKdsKey
  for s in $sqls; do
    say "step 2: login on $s"
    push_pkg "$s"
    v "$s" "sqlcmd -E -C -i C:\\sqlmcp\\02-sql-login.sql -v 'GmsaLogin=$gmsa_login'"
  done
  say "step 3: Data API builder on vm1"
  push_pkg vm1
  run_ps vm1 03-dab-install.ps1 -From "$agent_cidr,$vm_cidr"

  say "ADMIN STEP (an Entra admin, with their own az login; idempotent):"
  echo
  echo "  playbooks/sql-mcp/package/admin/entra-setup.sh --agent $agent_id"
  echo
  echo "then: direnv exec . playbooks/sql-mcp/tests/lab/lab-up.sh --app-id <APP_ID>"
  exit 0
fi

say "phase B: $env_name"
lab_load
echo "$appid" > "$(appid_file)"
servers=$(echo $sqls | tr ' ' ',')
say "step 4: configuration on vm1 ($servers), restart"
push_pkg vm1
run_ps vm1 04-dab-config.ps1 -Servers "$servers" -Domain "$domain" -TenantId "$tenant" -AppId "$appid"
dab_restart
say "step 5: connect the agent"
out=$(sh "$pb/package/agent/connect-agent.sh" --agent "$agent_id" --endpoint "http://$real1.$domain:5000/mcp" --app-id "$appid" 2>&1) || {
  echo "$out" | mask; echo "connect-agent FAILED"; exit 1; }
echo "$out" | mask
say "done. Next: the lab tests (playbooks/sql-mcp/tests/run.sh T11 ... T24)"
