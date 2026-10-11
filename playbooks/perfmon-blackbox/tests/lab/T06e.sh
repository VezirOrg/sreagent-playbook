#!/bin/sh
# T06e [vm1] (with MaxSizeMB=16, SampleIntervalSeconds=1, ExportEveryHours=24): the guest assignment is NonCompliant
# through R6 (BlackboxCapacity) and its reason names the buffer hours, the interval, MaxSizeMB and the export window.
# Back at the defaults the same check must be Compliant (run T04).
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
az rest --method get --url "https://management.azure.com$(machine_id "$m")/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox?api-version=2022-01-25" -o json |
python3 -c '
import json, sys
d = json.load(sys.stdin)["properties"]
rs = (d.get("latestAssignmentReport") or {}).get("resources") or []
cap = [r for r in rs if "Capacity" in (r.get("resourceId") or "")]
print("complianceStatus", d.get("complianceStatus"))
for r in cap:
    print("capacity", r.get("complianceStatus"), " | ".join(x.get("phrase", "") for x in r.get("reasons") or []))
ok = d.get("complianceStatus") == "NonCompliant" and cap and cap[0].get("complianceStatus") == "NonCompliant" and \
     all(w in " ".join(x.get("phrase", "") for x in cap[0].get("reasons") or []) for w in ("buffer holds", "at 1 s", "MaxSizeMB=16", "export every 24 h"))
print("RESULT", "PASS" if ok else "FAIL")' | mask | tee /dev/stderr | grep -q 'RESULT PASS'
