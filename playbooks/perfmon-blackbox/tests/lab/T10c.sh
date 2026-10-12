#!/bin/sh
# T10c [vm1]: block storage for one export (hosts-file entry for the storage name): the export
# fails (task result != 0) and state.json is unchanged; unblock: the next export covers both windows in one zip,
# complete: true, continuous with the export before. Since rc.8 (P46) the blocked run retries at +5 and +15 min before
# it fails, so it is waited for up to 30 min; T10d covers a block lifted during the retry.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
# the lab GPO turns Windows Firewall off on domain members, so storage is blocked by name: a hosts-file entry sends
# the account's FQDN to 127.0.0.2 for one export (the export runs as SYSTEM and uses the system resolver)
fq="$sa.blob.core.windows.net"
guest "$m" export-now.ps1 | grep '^state:'
v "$m" "Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value '127.0.0.2 $fq # BbT10c'; ipconfig /flushdns | Out-Null; 'blocked'"
f=$(guest "$m" export-now.ps1 -MaxWaitSeconds 1800); echo "$f"
v "$m" "(Get-Content C:\\Windows\\System32\\drivers\\etc\\hosts) | Where-Object { \$_ -notmatch 'BbT10c' } | Set-Content C:\\Windows\\System32\\drivers\\etc\\hosts; ipconfig /flushdns | Out-Null; 'unblocked'"
sleep 60
e=$(guest "$m" export-now.ps1); echo "$e"
vb=$(verify_blobs "$m" 2); echo "$vb"
echo "$f" | grep -q 'RESULT: FAIL' && ok 'blocked export failed' || bad 'blocked export did not fail'
s1=$(echo "$f" | grep '^state:' | sed 's/ last_error=.*//'); echo "$f" | grep -q 'last_error=.\+' && ok 'last_error recorded' || bad 'no last_error'
echo "$e" | grep -q 'RESULT: PASS' && ok 'next export uploaded' || bad 'next export failed'
echo "$vb" | grep -q 'RESULT: PASS' && ok 'both windows in one zip, continuous with the export before' || bad 'continuity check'
finish
