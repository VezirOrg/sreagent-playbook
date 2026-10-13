# wait until vm1 and arc1 report package 1.0.9 Compliant with 7 resources (rc.10 rollout), up to 80 min. Not committed.
. "$(dirname "$0")/common.sh"
for i in $(seq 1 40); do
  line=""; done_n=0
  for m in vm1 arc1; do
    s=$(ga_json $m | python3 -c 'import json,sys; d=json.load(sys.stdin); gc=d.get("guestConfiguration",{}); print(gc.get("version"), d.get("complianceStatus"), len(d.get("resources",[])), d.get("lastComplianceStatusChecked"))')
    line="$line | $m $s"
    case "$s" in "1.0.9 Compliant 7 "*) done_n=$((done_n+1)) ;; esac
  done
  echo "$(date -u +%H:%MZ)$line"
  [ $done_n -eq 2 ] && { echo BOTH-ON-RC10; exit 0; }
  sleep 120
done
echo NOT-REACHED; exit 1
