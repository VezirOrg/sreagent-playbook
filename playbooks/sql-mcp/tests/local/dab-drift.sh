#!/bin/sh
# L04: is the pinned Data API builder version still the latest stable release, and does the pinned SHA-256 match the
# digest GitHub publishes for its Windows zip? Read-only GitHub API (no Azure, no token needed). Not run in CI: a new
# upstream release is a signal for a playbook session, not a broken build.
# On a new version: run T24 (placeholder root), T14 and T21 with it on a copy (port 5001) before pinning it.
set -eu
pkg=$(cd "$(dirname "$0")/../../package" && pwd)
pin=$(sed -n "s/.*\[string\]\$Version = '\([^']*\)'.*/\1/p" "$pkg/03-dab-install.ps1")
sha=$(sed -n "s/^ *'$pin' = '\([0-9a-f]*\)'.*/\1/p" "$pkg/03-dab-install.ps1")
api=https://api.github.com/repos/Azure/data-api-builder/releases
latest=$(curl -fsS "$api/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')
digest=$(curl -fsS "$api/tags/v$pin" | python3 -c '
import json, sys
for a in json.load(sys.stdin)["assets"]:
    if a["name"].startswith("dab_net") and a["name"].endswith("win-x64-'"$pin"'.zip"):
        print((a.get("digest") or "").split(":")[-1])')
rc=0
echo "pinned $pin, latest stable $latest"
[ "$pin" = "$latest" ] || { echo "  DRIFT: a newer Data API builder exists; re-test T24, T14, T21 with it before pinning"; rc=1; }
if [ -z "$digest" ]; then echo "  GitHub publishes no digest for the pinned zip: check the hash by hand"; rc=1
elif [ "$digest" = "$sha" ]; then echo "  pinned SHA-256 matches GitHub's digest"
else echo "  SHA-256 MISMATCH between 03-dab-install.ps1 and GitHub"; rc=1; fi
exit $rc
