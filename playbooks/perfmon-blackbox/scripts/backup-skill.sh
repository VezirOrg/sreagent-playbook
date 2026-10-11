#!/bin/sh
# backup-skill.sh — save the LIVE version of an Azure SRE Agent skill as a zip, before any update (Emre's rule, P44).
#
#   SRE_AGENT_ID=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/agents/<agent> \
#     ./backup-skill.sh <skill-name> <out-dir>
#
# Writes <out-dir>/<skill-name>-v<version>-<yyyymmdd-hhmmss>Z.zip with SKILL.md and every additional file, exactly as the
# agent holds them (GET /api/v2/extendedAgent/skills/<name>). Prints the zip path and its SHA-256. Needs az + python3.
set -eu
name="${1:?usage: backup-skill.sh <skill-name> <out-dir>}"; out="${2:?usage: backup-skill.sh <skill-name> <out-dir>}"
: "${SRE_AGENT_ID:?set SRE_AGENT_ID to the ARM resource ID of the agent}"
ep=$(az rest -m GET --url "https://management.azure.com$SRE_AGENT_ID?api-version=2025-05-01-preview" --query properties.agentEndpoint -o tsv)
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
az rest -m GET --url "$ep/api/v2/extendedAgent/skills/$name" --resource https://azuresre.dev > "$tmp" || { echo "no live skill $name: nothing to back up"; exit 0; }
mkdir -p "$out"
python3 -I - "$tmp" "$out" "$name" <<'PY'
import hashlib, json, os, re, sys, time, zipfile
live = json.load(open(sys.argv[1]))['properties']; out, name = sys.argv[2], sys.argv[3]
m = re.search(r'version:\s*"?([\w.]+)"?', live.get('skillContent', ''))
path = os.path.join(out, f"{name}-v{m.group(1) if m else 'unknown'}-{time.strftime('%Y%m%d-%H%M%S', time.gmtime())}Z.zip")
with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('SKILL.md', live['skillContent'])
    for f in live.get('additionalFiles') or []:
        z.writestr(f['filePath'], f['content'])
print(path); print('sha256:', hashlib.sha256(open(path, 'rb').read()).hexdigest())
PY
