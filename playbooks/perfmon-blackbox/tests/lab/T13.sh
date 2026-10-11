#!/bin/sh
# T13: the lifecycle rule exists: prefix perfmon/, delete after RetentionDays (30), enabled.
. "$(dirname "$0")/common.sh"
r=$(az storage account management-policy show -g "$rg" --account-name "$sa" -o json)
check 'rule enabled' "$(echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin)["policy"]["rules"][0]; print(r["enabled"])')" True
check 'prefix' "$(echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin)["policy"]["rules"][0]; print(",".join(r["definition"]["filters"]["prefixMatch"]))')" 'perfmon/'
check 'delete after days' "$(echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin)["policy"]["rules"][0]; print(int(r["definition"]["actions"]["baseBlob"]["delete"]["daysAfterModificationGreaterThan"]))')" 30
finish
