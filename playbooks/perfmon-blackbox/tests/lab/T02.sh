#!/bin/sh
# T02: both definitions exist, one resource type each, contentUri/contentHash/version = the package under test
# (lab pbb-package.env), and the same parameters with the defaults of P19.
. "$(dirname "$0")/common.sh"
for kind in vm arc; do
  j=$(az policy definition show -n "perfmon-blackbox-$kind" -o json 2>/dev/null) || { bad "perfmon-blackbox-$kind missing"; continue; }
  echo "$j" | PKG_URI="${PKG_URI:-}" PKG_SHA256="${PKG_SHA256:-}" PKG_VERSION="${PKG_VERSION:-}" KIND=$kind python3 -c '
import json, os, sys
d = json.load(sys.stdin); k = os.environ["KIND"]
want = {"vm": "Microsoft.Compute/virtualMachines", "arc": "Microsoft.HybridCompute/machines"}[k]
t = d["policyRule"]["if"]["allOf"][0]["equals"]
gc = d["policyRule"]["then"]["details"]["deployment"]["properties"]["template"]["resources"][0]["properties"]["guestConfiguration"]
p = d["parameters"]
checks = [("type", t, want), ("contentUri", gc["contentUri"], os.environ["PKG_URI"]), ("contentHash", gc["contentHash"].upper(), os.environ["PKG_SHA256"].upper()),
          ("version", gc["version"], os.environ["PKG_VERSION"]), ("MaxSizeMB default", p["MaxSizeMB"].get("defaultValue"), "512"),
          ("SampleIntervalSeconds default", p["SampleIntervalSeconds"].get("defaultValue"), "10"), ("ExportEveryHours default", p["ExportEveryHours"].get("defaultValue"), "1"),
          ("parameters", ",".join(sorted(p)), "ContainerName,ExportEveryHours,LocalKeepMB,MaxSizeMB,SampleIntervalSeconds,StorageAccountResourceId,WriterRoleDefinitionId,effect")]
bad = 0
for n, a, e in checks:
    print(("  ok   " if a == e else "  FAIL ") + f"{k} {n} = {a}" + ("" if a == e else f" (expected {e})")); bad += a != e
sys.exit(1 if bad else 0)' || fails=$((fails + 1))
done
finish
