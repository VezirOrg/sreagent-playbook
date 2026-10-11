#!/bin/sh
# lab-params.sh [machine=vm1|arc1] k=v ...: change the policy parameters of that machine's lab assignment (e.g. MaxSizeMB=16) and remediate,
# then wait until the machine's config.json carries them (T06b-T06e, T10b). No args = the P19 defaults.
#   direnv exec . playbooks/perfmon-blackbox/tests/lab/lab-params.sh [machine=vm1] MaxSizeMB=16 SampleIntervalSeconds=1
. "$(dirname "$0")/common.sh"
m=vm1; kv=""
for a in "$@"; do case "$a" in machine=*) m="${a#machine=}" ;; *) kv="$kv $a" ;; esac; done
kind=vm; [ "$m" = arc1 ] && kind=arc   # only the machine's own assignment changes
KINDS=$kind REMEDIATION_MODE=ReEvaluateCompliance ARC_VM=$(az vm show -g "$rg" -n arc1 --query name -o tsv 2>/dev/null || true) \
  sh "$here/lab-policy.sh" "$PKG_URI" "$PKG_SHA256" "$PKG_VERSION" $kv | mask | tail -3
want=$(python3 -c 'import sys, json; d={"MaxSizeMB":"512","SampleIntervalSeconds":"10","ExportEveryHours":"4"}; [d.update([a.split("=",1)]) for a in sys.argv[1:]]; print(" ".join(f"{k}={d[k]}" for k in ("MaxSizeMB","SampleIntervalSeconds","ExportEveryHours")))' $kv)
echo "waiting until $m has: $want"
for i in $(seq 1 90); do
  got=$(v "$m" '$c = Get-Content C:\ProgramData\PerfmonBlackbox\config.json -Raw | ConvertFrom-Json; "MaxSizeMB=$($c.MaxSizeMB) SampleIntervalSeconds=$($c.SampleIntervalSeconds) ExportEveryHours=$($c.ExportEveryHours)"' | tr -d '\r' | tail -1)
  [ "$got" = "$want" ] && { echo "$(date -u +%H:%M:%S) reached: $got"; exit 0; }
  sleep 30
done
echo "not reached after 45 min (last: $got)"; exit 1
