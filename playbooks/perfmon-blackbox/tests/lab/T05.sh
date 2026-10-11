#!/bin/sh
# T05 [vm1|arc1]: vm1: extension AzurePolicyforWindows Succeeded, system identity; no pwsh on the server (P25).
# arc1: Connected, agent >= 1.10, system identity, IMDS blocked; no pwsh.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
if [ "$m" = arc1 ]; then
  # (the full JSON of an Arc machine can hold Windows paths with bad escapes: read fields with --query)
  set -- $(az connectedmachine show -g "$rg" -n arc1 --query "[status, agentVersion, identity.type]" -o tsv 2>/dev/null)
  check status "${1:-}" Connected
  python3 -c 'import sys; v=tuple(int(x) for x in sys.argv[1].split(".")[:2]); sys.exit(0 if v >= (1, 10) else 1)' "${2:-0.0}" && ok "agent ${2:-} >= 1.10" || bad "agent ${2:-} < 1.10"
  check identity "${3:-}" SystemAssigned
  imds=$(v arc1 '(Test-NetConnection 169.254.169.254 -Port 80 -WarningAction SilentlyContinue).TcpTestSucceeded')
  check 'IMDS reachable' "$(echo "$imds" | tr -d '\r' | tail -1)" False
else
  check extension "$(az vm extension show -g "$rg" --vm-name "$(vm_real vm1)" -n AzurePolicyforWindows --query provisioningState -o tsv 2>/dev/null)" Succeeded
  check identity "$(az vm show -g "$rg" -n "$(vm_real vm1)" --query identity.type -o tsv | tr -d ' ')" SystemAssigned
fi
p=$(v "$m" '@(Get-Command pwsh -ErrorAction SilentlyContinue).Count' | tr -d '\r' | tail -1)
check 'pwsh on the server' "$p" 0
finish
