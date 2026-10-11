#!/bin/sh
# T06e [vm1] (with MaxSizeMB=16, SampleIntervalSeconds=1, ExportEveryHours=24): the guest assignment is NonCompliant
# through R6 (BlackboxCapacity) and its reason names the buffer hours, the interval, MaxSizeMB and the export window.
# Back at the defaults the same check is Compliant (T04).
. "$(dirname "$0")/common.sh"
ga_json "${1:-vm1}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
cap = [r for r in d.get("resources", []) if "Capacity" in (r["id"] or "")]
print("complianceStatus", d.get("complianceStatus"))
for r in cap: print("capacity", r["status"], r["reasons"])
ok = d.get("complianceStatus") == "NonCompliant" and cap and cap[0]["status"] == "NonCompliant" and \
     all(w in cap[0]["reasons"] for w in ("buffer holds", "at 1 s", "MaxSizeMB=16", "export every 24 h"))
print("RESULT", "PASS" if ok else "FAIL")' | mask | tee /dev/stderr | grep -q 'RESULT PASS'
