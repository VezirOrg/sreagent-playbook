#!/bin/sh
# lab-arc1.sh: build arc1, an Azure VM prepared per Learn "Evaluate Azure Arc-enabled servers on an Azure virtual
# machine" (design sec. 5, decisions P6/P10), and onboard it to Azure Arc in the lab resource group.
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-arc1.sh
# Steps: (0) the VM policy and the VM prerequisites must already exclude arc1 (lab-policy.sh with ARC_VM=arc1);
# (1) Windows Server 2022 VM `arc1` in the lab's vm subnet, no public IP; (2) run command, while the guest agent still
# runs: OpenSSH server (Bastion access, as the template's VMs), MSFT_ARC_TEST, the Connected Machine agent installed;
# (3) every VM extension removed; (4) guest agent disabled and IMDS (169.254.169.254, .253) blocked; (5) over SSH:
# azcmagent connect with the lab service principal, from a config file that is deleted right after (the secret is
# never on a command line or printed). Stop condition P10: if any step fails, stop and report.
set -eu
. "$(dirname "$0")/common.sh"
loc=$(az group show -n "$rg" --query location -o tsv)
vnet=$(az network vnet list -g "$rg" --query "[0].name" -o tsv)
ns=$(az policy assignment show -n pbb-vm --scope "/subscriptions/$sub/resourceGroups/$rg" --query "notScopes[?ends_with(@, '/arc1')] | length(@)" -o tsv)
[ "$ns" = 1 ] || { echo "STOP: run lab-policy.sh with ARC_VM=arc1 first (arc1 must be outside the VM policy)"; exit 1; }

if ! az vm show -g "$rg" -n arc1 -o none 2>/dev/null; then
  echo "(1) creating arc1"
  az vm create -g "$rg" -n arc1 --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-g2:latest --size Standard_B2s_v2 \
    --vnet-name "$vnet" --subnet vm --public-ip-address "" --nsg "" --admin-username "$VM_ADMIN_USERNAME" \
    --admin-password "$VM_ADMIN_PASSWORD" --license-type Windows_Server -o none
fi

echo "(2) OpenSSH, MSFT_ARC_TEST, Connected Machine agent (run command)"
cat > "${TMPDIR:-/tmp}/arc1-prep.ps1" <<'PS'
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
if (-not (Get-Service sshd -ErrorAction SilentlyContinue)) { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null }
Set-Service sshd -StartupType Automatic; Start-Service sshd
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null
if (-not (Get-NetFirewallRule -Name sshd-lab -ErrorAction SilentlyContinue)) { New-NetFirewallRule -Name sshd-lab -DisplayName 'OpenSSH (lab)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null }
[Environment]::SetEnvironmentVariable('MSFT_ARC_TEST', 'true', 'Machine')
if (-not (Test-Path "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe")) {
  Invoke-WebRequest -UseBasicParsing -Uri https://aka.ms/AzureConnectedMachineAgent -OutFile "$env:TEMP\AzureConnectedMachineAgent.msi"
  $p = Start-Process msiexec.exe -ArgumentList '/i', "$env:TEMP\AzureConnectedMachineAgent.msi", '/qn', '/l*v', "$env:TEMP\azcmagent-install.log" -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "agent install exit $($p.ExitCode)" }
}
"sshd $((Get-Service sshd).Status); agent installed $(Test-Path "$env:ProgramFiles\AzureConnectedMachineAgent\azcmagent.exe")"
PS
az vm run-command invoke -g "$rg" -n arc1 --command-id RunPowerShellScript --scripts @"${TMPDIR:-/tmp}/arc1-prep.ps1" \
  --query "value[].message" -o tsv | mask
rm -f "${TMPDIR:-/tmp}/arc1-prep.ps1"

echo "(3) removing VM extensions"
for e in $(az vm extension list -g "$rg" --vm-name arc1 --query "[].name" -o tsv); do
  az vm extension delete -g "$rg" --vm-name arc1 -n "$e" -o none; echo "  removed $e"
done

echo "(4) guest agent disabled, IMDS blocked (the run command channel ends here)"
az vm run-command invoke -g "$rg" -n arc1 --command-id RunPowerShellScript --no-wait --scripts \
  "New-NetFirewallRule -Name BlockAzureIMDS -DisplayName 'Block access to Azure IMDS' -Enabled True -Profile Any -Direction Outbound -Action Block -RemoteAddress 169.254.169.254,169.254.169.253 | Out-Null; Set-Service WindowsAzureGuestAgent -StartupType Disabled; Stop-Service WindowsAzureGuestAgent -Force" -o none || true
sleep 90

echo "(5) azcmagent connect (service principal from the lab .env, via a config file deleted right after)"
cfg=$(mktemp); chmod 600 "$cfg"
python3 -c 'import json, os, sys
json.dump({"tenant-id": os.environ["AZURE_TENANT_ID"], "subscription-id": os.environ["AZURE_SUBSCRIPTION_ID"],
  "resource-group": sys.argv[1], "location": sys.argv[2], "resource-name": "arc1",
  "service-principal-id": os.environ["AZURE_CLIENT_ID"], "service-principal-secret": os.environ["AZURE_CLIENT_SECRET"]},
  open(sys.argv[3], "w"))' "$rg" "$loc" "$cfg"
(cd "$lab" && scripts/vmscp --user "$VM_ADMIN_USERNAME" arc1 "$cfg" C:/ProgramData/arc1-connect.json) >/dev/null 2>&1
rm -f "$cfg"
(cd "$lab" && scripts/vmssh --user "$VM_ADMIN_USERNAME" arc1 "try { & \"\$env:ProgramFiles\\AzureConnectedMachineAgent\\azcmagent.exe\" connect --config C:\\ProgramData\\arc1-connect.json 2>&1 | Select-Object -Last 3 } finally { Remove-Item C:\\ProgramData\\arc1-connect.json -Force -ErrorAction SilentlyContinue }; 'config file removed: ' + -not (Test-Path C:\\ProgramData\\arc1-connect.json)") 2>&1 | grep -v '^direnv:' | mask
az connectedmachine show -g "$rg" -n arc1 --query "{status:status, agent:agentVersion, identity:identity.type}" -o tsv
