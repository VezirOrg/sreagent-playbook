#!/bin/sh
# T10c [vm1]: block storage for one export (outbound firewall rule to the storage private endpoint IP): the export
# fails (task result != 0) and state.json is unchanged; unblock: the next export covers both windows in one zip,
# complete: true, continuous with the export before.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
nic=$(az network private-endpoint show -g "$rg" -n "pe-$sa-blob" --query "networkInterfaces[0].id" -o tsv)
ip=$(az network nic show --ids "$nic" --query "ipConfigurations[0].privateIPAddress" -o tsv)
[ -n "$ip" ] || { bad 'no private endpoint IP'; finish; exit 1; }
guest "$m" export-now.ps1 | grep '^state:'
v "$m" "New-NetFirewallRule -Name BbT10c -DisplayName 'T10c block storage' -Direction Outbound -RemoteAddress $ip -Action Block | Out-Null; 'blocked'"
f=$(guest "$m" export-now.ps1); echo "$f"
v "$m" "Remove-NetFirewallRule -Name BbT10c; 'unblocked'"
sleep 60
e=$(guest "$m" export-now.ps1); echo "$e"
vb=$(verify_blobs "$m" 2); echo "$vb"
echo "$f" | grep -q 'RESULT: FAIL' && ok 'blocked export failed' || bad 'blocked export did not fail'
s1=$(echo "$f" | grep '^state:' | sed 's/ last_error=.*//'); echo "$f" | grep -q 'last_error=.\+' && ok 'last_error recorded' || bad 'no last_error'
echo "$e" | grep -q 'RESULT: PASS' && ok 'next export uploaded' || bad 'next export failed'
echo "$vb" | grep -q 'RESULT: PASS' && ok 'both windows in one zip, continuous with the export before' || bad 'continuity check'
finish
