#!/bin/sh
# T04 [vm1|arc1]: guest assignment PerfmonBlackbox Compliant, checked < 30 min ago, all 6 resources Compliant.
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"
j=$(az rest --method get --url "https://management.azure.com$(machine_id "$m")/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox?api-version=2022-01-25" -o json 2>&1) || { echo "$j" | mask; bad 'no guest assignment'; finish; exit 1; }
echo "$j" | python3 -c '
import json, sys, datetime as dt
d = json.load(sys.stdin)["properties"]
print("complianceStatus", d.get("complianceStatus"))
print("lastComplianceStatusChecked", d.get("lastComplianceStatusChecked"))
t = d.get("lastComplianceStatusChecked")
age = (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(t.replace("Z", "+00:00"))).total_seconds() / 60 if t else 1e9
print("age_min %.1f" % age)
rs = ((d.get("latestAssignmentReport") or {}).get("resources") or [])
for r in rs:
    rid = (r.get("resourceId") or "")
    why = " | ".join(x.get("phrase", "") for x in (r.get("reasons") or []))
    print("resource", rid, r.get("complianceStatus"), why[:300])
ok = d.get("complianceStatus") == "Compliant" and age < 30 and len(rs) == 6 and all(r.get("complianceStatus") == "Compliant" for r in rs)
print("RESULT", "PASS" if ok else "FAIL")' | mask | tee /dev/stderr | grep -q 'RESULT PASS'
