#!/bin/sh
# T18de.sh <d|e|restore|watch>: T18d and T18e on arc1 in storage mode, run as a package rollout (P45, P56). An unchanged
# re-PUT does not make the agent download again (it keeps the package it holds), so the steps move arc1 to a NEW
# package (NEW_URI, NEW_SHA256, NEW_VERSION; the container still holds the old one). Each step but 'watch' ends with a
# re-PUT of arc1's guest assignment built from the policy definition (ARM hides contentUri); run 'watch' ~10 min later.
#   d       : no reader role on the package container; the arc storage definition updated to the new package
#             (DEFS_ONLY, no remediation: it would grant the role)                -> expect 403, old package keeps running
#   e       : the reader role back; the container still holds the old zip under the same name -> expect the hash check
#             to reject it, old package keeps running
#   restore : the new package uploaded to the container                          -> then 'T18.sh arc1 storage' (with
#             pbb-package.env on the new package)
#   watch   : the agent's download lines since the last step, then 'T18.sh arc1 nodownload'
. "$(dirname "$0")/common.sh"
step="${1:-watch}"; m=arc1
t0f="$lab/t18de.t0"
cid="$(az storage account show -g "$rg" -n "$sa" --query id -o tsv)/blobServices/default/containers/packages"
pid=$(az connectedmachine show -g "$rg" -n arc1 --query identity.principalId -o tsv)
need_new() { [ -n "${NEW_URI:-}" ] && [ -n "${NEW_SHA256:-}" ] && [ -n "${NEW_VERSION:-}" ] || { echo "set NEW_URI, NEW_SHA256, NEW_VERSION"; exit 2; }; }
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
    need_new
    for ra in $(az role assignment list --assignee-object-id "$pid" --role "Storage Blob Data Reader" --scope "$cid" --query "[].id" -o tsv); do
      az role assignment delete --ids "$ra" -o none && echo "removed arc1's reader role on the package container"; done
    DEFS_ONLY=1 KINDS=arc sh "$here/lab-policy.sh" "$NEW_URI" "$NEW_SHA256" "$NEW_VERSION" "PackageContainerResourceId=$cid" | mask | tail -1
    sleep 60; reput ;;
  e)
    az role assignment create --assignee-object-id "$pid" --assignee-principal-type ServicePrincipal \
      --role "Storage Blob Data Reader" --scope "$cid" -o none && echo "reader role on the package container again (container unchanged)"
    sleep 60; reput ;;
  restore)
    need_new
    guest dc upload-package.ps1 -Url "$NEW_URI" -Sha256 "$NEW_SHA256" -Account "$sa" | grep -v '^$'
    reput ;;
  watch)
    since=$(cat "$t0f" 2>/dev/null || echo 0)
    v $m "Get-Content C:\\ProgramData\\GuestConfig\\arc_policy_logs\\gc_agent.log -Tail 20000 | Select-String -Pattern 'Download assignment package for : PerfmonBlackbox|Failed to (download|validate)|PerfmonBlackbox.*compliance status' | % { \$_.Line } | ? { \$_.Substring(1, 19) -ge '$since' } | Select-Object -Last 12 | % { \$_ -replace '\] \[PID.*?\] \[(INFO|ERROR|WARNING)\] (\[[^]]*\] )?', '] ' }" \
      | tr -d '\r' | perl -pe 's/stbb\w+/<account>/g' | cut -c1-220
    sh "$here/T18.sh" $m nodownload ;;
  *) echo "usage: T18de.sh d|e|restore|watch"; exit 2 ;;
esac
