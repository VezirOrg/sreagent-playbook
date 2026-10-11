#!/bin/sh
# T06d [vm1] (run lab-params.sh ... SampleIntervalSeconds=1 after a period at 10 s): the collector samples at the
# new interval: logman shows it, and the timestamps of the last minutes in the next export step by 1 s (+-10 %).
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
c=$(guest "$m" collector.ps1); echo "$c" | head -2
e=$(guest "$m" export-now.ps1); echo "$e" | tail -2
vb=$(verify_blobs "$m" 1 -AllowIncomplete); echo "$vb"
echo "$c" | grep -q "interval=${2:-1} " && ok "collector interval ${2:-1} s" || bad "collector interval not ${2:-1} s"
step=$(echo "$vb" | sed -n 's/.*last 60 samples median \([0-9.]*\) s.*/\1/p' | head -1)
python3 -c 'import sys; sys.exit(0 if abs(float(sys.argv[1]) - float(sys.argv[2])) <= 0.1 * float(sys.argv[2]) else 1)' "${step:-99}" "${2:-1}" && ok "median step of the last samples $step s" || bad "median step $step s"
finish
