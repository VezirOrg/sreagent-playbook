#!/bin/sh
# T18 [vm1|arc1] <storage|github|nodownload>: the package source (P45).
#   storage   : the guest assignment points at the package container (contentUri .../packages/PerfmonBlackbox.zip,
#               contentManagedIdentity system), carries the SAME contentHash as the release, is Compliant, the machine
#               holds the reader role on the package container only, and the collector + an export still work (T18b/c).
#   github    : the assignment points at the release asset again, Compliant, same hash (T18a, and the way back for T18c).
#   nodownload: storage mode while the package cannot be used (no reader role, T18d; or a different zip under the same
#               name, T18e): the assignment is NOT Compliant on the new content and the machine keeps running its old
#               configuration (collector Running, files unchanged). Prints what the assignment shows.
. "$(dirname "$0")/common.sh"
m="${1:-arc1}"; mode="${2:-storage}"
ga=$(ga_json "$m")
echo "$ga" | MODE="$mode" PKG_SHA256="$PKG_SHA256" python3 -c '
import json, os, sys
d = json.load(sys.stdin); g = d.get("guestConfiguration") or {}; mode = os.environ["MODE"]
print("status", d.get("complianceStatus"), "| uri", (g.get("contentUri") or "").split("/")[-2:], "| identity", g.get("contentManagedIdentity"),
      "| hash ok", (g.get("contentHash") or "").upper() == os.environ["PKG_SHA256"].upper())
for r in d.get("resources", []): print("  resource", r["id"], r["status"], r["reasons"][:160])
if mode == "storage":
    # ARM hides contentUri and contentManagedIdentity of this assignment (both API versions); the source and the identity
    # are checked in the agent log below
    ok = d.get("complianceStatus") == "Compliant" and (g.get("contentHash") or "").upper() == os.environ["PKG_SHA256"].upper()
elif mode == "github":
    # contentUri is hidden here too: the source is checked in the agent log below
    ok = d.get("complianceStatus") == "Compliant" and (g.get("contentHash") or "").upper() == os.environ["PKG_SHA256"].upper() \
         and not g.get("contentManagedIdentity")
else:
    ok = d.get("complianceStatus") != "Compliant"
print("ASSIGNMENT", "PASS" if ok else "FAIL")' | mask > /tmp/t18.$$; cat /tmp/t18.$$
grep -q 'ASSIGNMENT PASS' /tmp/t18.$$ && ok "assignment as expected for $mode" || bad "assignment not as expected for $mode"; rm -f /tmp/t18.$$
if [ "$mode" != nodownload ]; then
  # the agent's own record of the last package download: source, identity, result
  log='C:\ProgramData\GuestConfig\gc_agent_logs\gc_agent.log'; [ "$m" = arc1 ] && log='C:\ProgramData\GuestConfig\arc_policy_logs\gc_agent.log'
  dl=$(v "$m" "Get-Content '$log' -Tail 20000 | Select-String -Pattern 'Download assignment package for : PerfmonBlackbox|Downloading package to .*PerfmonBlackbox|Failed to download (file|assignment)' | Select-Object -Last 8 | % { \$_.Line -replace '^.*\] ', '' }" | tr -d '\r' | perl -pe 's/stbb\w+/<account>/g' \
    | awk '/^Download assignment package for/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }')   # the last attempt only
  echo "$dl" | cut -c1-200
  if [ "$mode" = storage ]; then
    echo "$dl" | grep -q 'from private blob using managed identity' && echo "$dl" | grep -q '/packages/PerfmonBlackbox.zip' \
      && ! echo "$dl" | grep -q 'Failed to download' && ok 'last download: storage, own managed identity, no error' || bad 'last download not from storage with the managed identity'
  else
    echo "$dl" | grep -q 'github.com/' && ! echo "$dl" | grep -q 'Failed to download' && ok 'last download: GitHub, no error' || bad 'last download not from GitHub'
  fi
fi
if [ "$mode" = storage ]; then
  pid=$( [ "$m" = arc1 ] && az connectedmachine show -g "$rg" -n arc1 --query identity.principalId -o tsv 2>/dev/null || az vm show -g "$rg" -n "$(vm_real "$m")" --query identity.principalId -o tsv)
  roles=$(az role assignment list --assignee "$pid" --all --query "[].[roleDefinitionName, scope]" -o tsv 2>/dev/null | perl -pe 's#\t.*/containers/# container:#; s#\t# #' | sort)
  echo "$roles" | mask
  echo "$roles" | grep -q 'Storage Blob Data Reader container:packages' && ok 'reader on the package container' || bad 'no reader role on the package container'
  echo "$roles" | grep 'Storage Blob Data Reader' | grep -vq 'container:packages' && bad 'reader role outside the package container' || ok 'no reader role elsewhere'
fi
c=$(guest "$m" collector.ps1); echo "$c" | head -1
echo "$c" | grep -q 'status=Running' && ok 'collector running' || bad 'collector not running'
if [ "$mode" != nodownload ]; then e=$(guest "$m" export-now.ps1); echo "$e" | tail -1; echo "$e" | grep -q 'RESULT: PASS' && ok 'export works' || bad 'export failed'; fi
finish
