#!/bin/sh
# T08 [vm1|arc1]: restart the machine; within 3 min of boot the collector runs, the Boot task ran after the boot with
# result 0, the pre-reboot ring is pending; the next export holds the pre-reboot samples with only a machine_off gap.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
if [ "$m" = arc1 ]; then az vm restart -g "$rg" -n arc1 -o none; else az vm restart -g "$rg" -n "$(vm_real vm1)" -o none; fi
echo "  restarted; waiting 180 s"; sleep 180
out=$(guest "$m" after-boot.ps1); echo "$out"
e=$(guest "$m" export-now.ps1); echo "$e"
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb"
echo "$out" | grep -q 'RESULT: PASS' && echo "$e" | grep -q 'RESULT: PASS' && echo "$vb" | grep -q 'RESULT: PASS' &&
  ! echo "$vb" | grep 'gap ' | grep -v 'machine_off' | grep -q . && echo "$vb" | grep -q 'machine_off'
