#!/bin/sh
# T14: the storage is private: no anonymous access, no shared key, TLS >= 1.2, public network access disabled,
# an approved private endpoint, container private; an anonymous GET and a shared-key request both fail.
. "$(dirname "$0")/common.sh"
j=$(az storage account show -g "$rg" -n "$sa" -o json)
p() { echo "$j" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
check allowBlobPublicAccess "$(p 'd["allowBlobPublicAccess"]')" False
check allowSharedKeyAccess "$(p 'd["allowSharedKeyAccess"]')" False
check minimumTlsVersion "$(p 'd["minimumTlsVersion"]')" TLS1_2
check publicNetworkAccess "$(p 'd["publicNetworkAccess"]')" Disabled
check 'private endpoint approved' "$(p 'sorted({c["privateLinkServiceConnectionState"]["status"] for c in d.get("privateEndpointConnections") or []} or {"none"})[0]')" Approved
code=$(curl -s -o /dev/null -w '%{http_code}' "https://$sa.blob.core.windows.net/$container?restype=container&comp=list")
case "$code" in 4??) ok "anonymous list refused (HTTP $code)" ;; *) bad "anonymous list returned HTTP $code" ;; esac
if az storage blob list --account-name "$sa" -c "$container" --auth-mode key -o none 2>/dev/null; then bad 'shared-key request succeeded'; else ok 'shared-key request refused'; fi
finish
