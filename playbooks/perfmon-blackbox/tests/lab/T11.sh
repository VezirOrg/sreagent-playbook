#!/bin/sh
# T11 [vm1|arc1]: the newest blob is at perfmon/<sub>/<rg>/<machine>/<yyyy>/<mm>/<dd>/<machine>_<from>_<to>.zip, its
# Content-MD5 and sha256 metadata match the zip, and it was uploaded with the machine's identity (IMDS on vm1, HIMDS on arc1).
. "$(dirname "$0")/common.sh"
m="${1:-vm1}"; want=imds; [ "$m" = arc1 ] && want=himds
vb=$(verify_blobs "$m" 1); echo "$vb" | grep -E '^zip|manifest:|RESULT'
echo "$vb" | grep -Eq "^zip [^ ]+/rg-[^/]+/$m/[0-9]{4}/[0-9]{2}/[0-9]{2}/${m}_[0-9]{8}-[0-9]{6}_[0-9]{8}-[0-9]{6}\.zip:" && ok 'blob path' || bad 'blob path'
echo "$vb" | grep -q 'metadata sha256 ok=True Content-MD5 ok=True' && ok 'sha256 metadata and Content-MD5 match' || bad 'hash mismatch'
echo "$vb" | grep -q "identity=$want" && ok "uploaded with the machine identity ($want)" || bad "identity not $want"
finish
