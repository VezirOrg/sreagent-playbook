#!/bin/sh
# T11: steps 1-4 run a second time change nothing: same gMSA, same SQL login and role, no new download, the same
# configuration content (04 only adds a backup folder), the task still runs.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
before=$(guest vm1 host-state.ps1)
out1=$(run_ps dc 01-ad-prep.ps1 -McpHost "$real1" -LabBackdateKdsKey)
echo "$out1" | grep -q 'gmsa-sqlmcp' && ok "01 rerun: gMSA present" || bad "01 rerun: $out1"
for s in $sqls; do
  o=$(v "$s" "sqlcmd -E -C -h -1 -W -i C:\\sqlmcp\\02-sql-login.sql -v 'GmsaLogin=$netbios\\gmsa-sqlmcp\$'")
  echo "$o" | grep -q 'MS_ServerPerformanceStateReader' && ok "02 rerun on $s: login + role" || bad "02 rerun on $s: $o"
done
o3=$(run_ps vm1 03-dab-install.ps1 -From "$(agent_subnet),$(subnet_of_vm vm1)")
echo "$o3" | grep -q 'task registered' && ok "03 rerun completes" || bad "03 rerun: $o3"
v vm1 'if (Test-Path C:\dab\dab_net10.0_win-x64-*.zip) { (Get-Item C:\dab\dab_net10.0_win-x64-*.zip).LastWriteTimeUtc.ToString("o") }' > "$lab/.t11-zip"
run_ps vm1 04-dab-config.ps1 -Servers "$(echo $sqls | tr ' ' ',')" -Domain "$domain" -TenantId "$tenant" -AppId "$(app_id)" >/dev/null
dab_restart >/dev/null
after=$(guest vm1 host-state.ps1)
check "config content after 04 rerun" "$(echo "$after" | kv CONFIG_HASH)" "$(echo "$before" | kv CONFIG_HASH)"
check "config files" "$(echo "$after" | kv CONFIG_FILES)" "$(echo "$before" | kv CONFIG_FILES)"
check "firewall remote" "$(echo "$after" | kv FW_REMOTE)" "$(echo "$before" | kv FW_REMOTE)"
check "task" "$(echo "$after" | kv TASK_STATE)" "Running"
z2=$(v vm1 'if (Test-Path C:\dab\dab_net10.0_win-x64-*.zip) { (Get-Item C:\dab\dab_net10.0_win-x64-*.zip).LastWriteTimeUtc.ToString("o") }')
check "DAB zip not downloaded again" "$z2" "$(cat "$lab/.t11-zip")"; rm -f "$lab/.t11-zip"
finish
