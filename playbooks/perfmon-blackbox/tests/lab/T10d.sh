#!/bin/sh
# T10d [vm1]: a failed upload retries itself in the same run (P46, rc.8 and later). Storage is blocked by name (as in
# T10c), the Export task is started, the block is lifted after ~3 min while the run waits for its +5-min attempt:
# the same run logs "upload attempt 1 failed ... retry in 300 s" and "uploaded on attempt 2", the task result is 0,
# last_error is empty, and the zip is complete and continuous with the export before (one zip, no gap, no overlap).
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
fq="$sa.blob.core.windows.net"
log='C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log'
unblock() { v "$m" "(Get-Content C:\\Windows\\System32\\drivers\\etc\\hosts) | Where-Object { \$_ -notmatch 'BbT10d' } | Set-Content C:\\Windows\\System32\\drivers\\etc\\hosts; ipconfig /flushdns | Out-Null; 'unblocked'"; }
trap unblock EXIT   # never leave the storage blocked
guest "$m" export-now.ps1 | grep -E '^(state:|RESULT)'          # a clean export before, for the continuity check
t0=$(date -u +%Y-%m-%dT%H:%M:%SZ)
v "$m" "Add-Content -Path C:\\Windows\\System32\\drivers\\etc\\hosts -Value '127.0.0.2 $fq # BbT10d'; ipconfig /flushdns | Out-Null; 'blocked'"
guest "$m" export-now.ps1 -StartOnly
echo "  waiting 180 s (attempt 1 fails, the run sleeps 300 s)"; sleep 180
unblock; trap - EXIT
e=$(guest "$m" export-now.ps1 -MaxWaitSeconds 1500 | tr -d '\r'); echo "$e"   # waits for the same run (IgnoreNew: no second run)
l=$(v "$m" "Get-Content $log -Tail 80" | tr -d '\r' | awk -v t0="$t0" '$1 >= t0 && /export/')   # this run's lines only
echo "$l"
vb=$(verify_blobs "$m" 2); echo "$vb"
echo "$l" | grep -q 'upload attempt 1 failed.*retry in 300 s' && ok 'attempt 1 failed, retry in 300 s' || bad 'no failed attempt 1 in the log'
echo "$l" | grep -q 'uploaded on attempt 2' && ok 'uploaded on attempt 2 (same run)' || bad 'not uploaded on attempt 2'
echo "$l" | grep -q 'upload attempt 2 failed' && bad 'attempt 2 failed (block lifted too late?)' || ok 'no second failure'
echo "$e" | grep -q 'RESULT: PASS' && ok 'task result 0' || bad 'task result not 0'
echo "$e" | grep -q 'last_error=$' && ok 'last_error empty' || bad 'last_error set'
echo "$vb" | grep -q 'RESULT: PASS' && ok 'zip complete, continuous with the export before' || bad 'continuity check'
finish
