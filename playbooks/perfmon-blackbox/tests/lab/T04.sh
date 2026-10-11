#!/bin/sh
# T04 [vm1|arc1]: guest assignment PerfmonBlackbox Compliant, checked < 30 min ago, all 6 resources Compliant
# (from the latest assignment report).
. "$(dirname "$0")/common.sh"
ga_json "${1:-vm1}" | python3 -c '
import json, sys, datetime as dt
d = json.load(sys.stdin)
t = d.get("lastComplianceStatusChecked")
age = (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(t.replace("Z", "+00:00"))).total_seconds() / 60 if t else 1e9
print("complianceStatus", d.get("complianceStatus"), "checked", t, "age_min %.1f" % age)
for r in d.get("resources", []):
    print("resource", r["id"], r["status"], r["reasons"][:200])
rs = d.get("resources", [])
ok = d.get("complianceStatus") == "Compliant" and age < 30 and len(rs) == 6 and all(r["status"] == "Compliant" for r in rs)
print("RESULT", "PASS" if ok else "FAIL")' | mask | tee /dev/stderr | grep -q 'RESULT PASS'
