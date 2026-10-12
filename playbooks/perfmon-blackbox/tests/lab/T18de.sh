#!/bin/sh
# T18de.sh <d|e|restore|watch>: T18d and T18e on arc1 in storage mode (P45, P56). Each step but 'watch' ends with an
# unchanged re-PUT of arc1's guest assignment (body built from the policy definition, since ARM hides contentUri) so
# the agent downloads the package again within ~5 min; then run 'watch' (or T18.sh) after ~10 min.
#   d       : remove arc1's Storage Blob Data Reader on the package container      -> expect 403, not Compliant
#   e       : (reader role in place) a different zip (rc.7) as PerfmonBlackbox.zip  -> expect the hash check to reject it
#   restore : the reader role back and the release zip back                        -> then 'T18.sh arc1 storage'
#   watch   : the agent's download lines since the last step, then 'T18.sh arc1 nodownload'
. "$(dirname "$0")/common.sh"
step="${1:-watch}"; m=arc1
t0f="$lab/t18de.t0"
cid="$(az storage account show -g "$rg" -n "$sa" --query id -o tsv)/blobServices/default/containers/packages"
pid=$(az connectedmachine show -g "$rg" -n arc1 --query identity.principalId -o tsv)
OTHER_URI="${OTHER_URI:-$(echo "$PKG_URI" | sed 's/rc\.8/rc.7/')}"
OTHER_SHA256="${OTHER_SHA256:-011ABABE14A8F4D720DAE32025679821569CAE18071EE06696F2F923441B673B}"   # rc.7 (decisions.md)
reput() { # the same guest assignment again: guestConfiguration from the definition, parameter values from ARM
  base="https://management.azure.com$(machine_id $m)/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox?api-version=2024-04-05"
  cur=$(az rest --method get --url "$base" -o json)
  def=$(az policy definition show -n perfmon-blackbox-arc-storage --query metadata.guestConfiguration -o json)
  loc=$(az connectedmachine show -g "$rg" -n arc1 --query location -o tsv)
  f=$(mktemp)
  python3 -c '
import json, sys
cur = json.loads(sys.argv[1]); g = json.loads(sys.argv[2])
gc = {k: g[k] for k in ("name", "version", "contentUri", "contentHash", "contentType", "contentManagedIdentity", "assignmentType")}
gc["configurationParameter"] = cur["properties"]["guestConfiguration"].get("configurationParameter") or []
json.dump({"location": sys.argv[3], "properties": {"guestConfiguration": gc}}, open(sys.argv[4], "w"))' "$cur" "$def" "$loc" "$f"
  az rest --method put --url "$base" --body "@$f" --query "properties.provisioningState" -o tsv; rm -f "$f"
  date -u +'%Y-%m-%d %H:%M:%S' > "$t0f"; echo "re-PUT at $(cat "$t0f")Z; run 'T18de.sh watch' in ~10 min"; }
case "$step" in
  d)
    for ra in $(az role assignment list --assignee-object-id "$pid" --role "Storage Blob Data Reader" --scope "$cid" --query "[].id" -o tsv); do
      az role assignment delete --ids "$ra" -o none && echo "removed arc1's reader role on the package container"; done
    sleep 60; reput ;;
  e)
    guest dc upload-package.ps1 -Url "$OTHER_URI" -Sha256 "$OTHER_SHA256" -Account "$sa" | grep -v '^$'; reput ;;
  restore)
    az role assignment create --assignee-object-id "$pid" --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Reader" --scope "$cid" -o none && echo "reader role on the package container again"
    guest dc upload-package.ps1 -Url "$PKG_URI" -Sha256 "$PKG_SHA256" -Account "$sa" | grep -v '^$'
    sleep 60; reput ;;
  watch)
    since=$(cat "$t0f" 2>/dev/null || echo 0)
    v $m "Get-Content C:\\ProgramData\\GuestConfig\\arc_policy_logs\\gc_agent.log -Tail 20000 | Select-String -Pattern 'Download assignment package for : PerfmonBlackbox|Failed to (download|validate)|PerfmonBlackbox.*compliance status' | % { \$_.Line } | ? { \$_.Substring(1, 19) -ge '$since' } | Select-Object -Last 12 | % { \$_ -replace '\] \[PID.*?\] \[(INFO|ERROR|WARNING)\] (\[[^]]*\] )?', '] ' }" \
      | tr -d '\r' | perl -pe 's/stbb\w+/<account>/g' | cut -c1-220
    sh "$here/T18.sh" $m nodownload ;;
  *) echo "usage: T18de.sh d|e|restore|watch"; exit 2 ;;
esac
