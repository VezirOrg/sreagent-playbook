#!/bin/sh
# watch-gc.sh [vm1|arc1] [minutes]: print, as they appear, the machine's package downloads (source and identity) from
# the Machine Configuration agent log, and every successful write of its guest assignment in the activity log (who:
# this playbook's policy identities or another app). For T18b/T18c (P48): a flip back to GitHub shows as
# "Managed identity not provided" after a PUT by another app.
. "$(dirname "$0")/common.sh"
m="${1:-arc1}"; mins="${2:-60}"
log='C:\ProgramData\GuestConfig\gc_agent_logs\gc_agent.log'; [ "$m" = arc1 ] && log='C:\ProgramData\GuestConfig\arc_policy_logs\gc_agent.log'
start=$(date -u +%Y-%m-%dT%H:%M:%SZ); seen=$(mktemp); trap 'rm -f "$seen"' EXIT
pids=""; for a in pbb-vm pbb-arc pbb-vm-storage pbb-arc-storage; do
  p=$(az policy assignment show -n "$a" --scope "/subscriptions/$sub/resourceGroups/$rg" --query identity.principalId -o tsv 2>/dev/null) && pids="$pids $p=$a"
done
# lines already in the log are the baseline
v "$m" "Get-Content '$log' -Tail 3000 | Select-String -Pattern 'Managed identity|Download assignment package for : PerfmonBlackbox|Failed to download|compliance status' | % { \$_.Line }" | tr -d '\r' > "$seen"
end=$(( $(date +%s) + mins * 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
  v "$m" "Get-Content '$log' -Tail 3000 | Select-String -Pattern 'Managed identity|Download assignment package for : PerfmonBlackbox|Failed to download|compliance status' | % { \$_.Line }" \
    | tr -d '\r' | while read -r l; do grep -qxF "$l" "$seen" || { echo "$l" >> "$seen"; echo "LOG $l" | perl -pe 's/\[PID \d+\] \[TID \d+\] //; s/\[<guid>\] //g; s/stbb\w+/<account>/g' | cut -c1-220; }; done
  az monitor activity-log list -g "$rg" --start-time "$start" --query "[?contains(resourceId,'/$(vm_real "$m" | tr 'A-Z' 'a-z')/providers/Microsoft.GuestConfiguration') || contains(resourceId,'/${m}/providers/Microsoft.GuestConfiguration')] | [?status.value=='Succeeded'].[eventTimestamp, claims.\"http://schemas.microsoft.com/identity/claims/objectidentifier\"]" -o tsv 2>/dev/null \
    | while read -r t o; do grep -qxF "PUT $t" "$seen" && continue; echo "PUT $t" >> "$seen"
        who=other-app; for x in $pids; do [ "${x%%=*}" = "$o" ] && who="${x#*=} identity"; done; echo "PUT $t by $who"; done
  sleep 60
done
