#!/bin/sh
# deploy-skill.sh — create or update an Azure SRE Agent skill from a folder, through the data plane API.
#
#   SRE_AGENT_ID=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/agents/<agent> \
#     ./deploy-skill.sh <skill-folder> [--apply]
#
# The folder holds SKILL.md (front matter: name, description) and the supporting files (all other files, flat).
# Without --apply it is a DRY RUN: it builds the request body, GETs the live skill (if any) and prints what would
# change. With --apply it PUTs /api/v2/extendedAgent/skills/<name>, GETs it back and checks every file byte for byte.
# Needs: az CLI signed in as a principal with "SRE Agent Administrator" on the agent; python3.
# The ARM path (Microsoft.App/agents/skills) is not used: in our tenant it answers "internal tenants only".
set -eu
dir="${1:?usage: deploy-skill.sh <skill-folder> [--apply]}"
apply="${2:-}"
: "${SRE_AGENT_ID:?set SRE_AGENT_ID to the ARM resource ID of the agent}"
tmp=$(mktemp -d)
cleanup() { rm -f "$tmp/body.json" "$tmp/live.json" "$tmp/after.json"; rmdir "$tmp"; }
trap cleanup EXIT

python3 -I - "$dir" "$tmp/body.json" <<'PY'
import json, os, re, sys
d, out = sys.argv[1], sys.argv[2]
skill = open(os.path.join(d, 'SKILL.md'), encoding='utf-8').read()
fm = re.match(r'^---\n(.*?)\n---\n', skill, re.S)
if not fm:
    sys.exit('SKILL.md has no front matter')
meta = dict(re.findall(r'^(name|description):\s*(.*)$', fm.group(1), re.M))
files = []
for f in sorted(os.listdir(d)):
    p = os.path.join(d, f)
    if f == 'SKILL.md' or f.startswith('.') or not os.path.isfile(p) or f.endswith(('.sh', '.zip')) or f == 'UPLOAD.md':
        continue
    files.append({'filePath': f, 'content': open(p, encoding='utf-8').read()})
body = {'name': meta['name'], 'type': 'Skill',
        'properties': {'description': meta['description'], 'skillContent': skill, 'additionalFiles': files, 'tools': []}}
json.dump(body, open(out, 'w'))
print(f"skill {meta['name']}: SKILL.md {len(skill)} chars; files: " +
      ', '.join(f"{x['filePath']} ({len(x['content'])} chars)" for x in files))
PY
name=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$tmp/body.json")
ep=$(az rest -m GET --url "https://management.azure.com$SRE_AGENT_ID?api-version=2025-05-01-preview" \
     --query properties.agentEndpoint -o tsv)
url="$ep/api/v2/extendedAgent/skills/$name"

compare() {  # $1 = live JSON file; prints per-part same/changed/new/removed
  python3 -I - "$tmp/body.json" "$1" <<'PY'
import json, sys
want = json.load(open(sys.argv[1]))['properties']
try:
    live = json.load(open(sys.argv[2]))['properties']
except Exception:
    print('live: no such skill (would be created)'); sys.exit(0)
ok = True
for k in ('description', 'skillContent', 'tools'):
    same = want[k] == live.get(k); ok &= same
    print(f"{k}: {'same' if same else 'CHANGED'}")
w = {f['filePath']: f['content'] for f in want['additionalFiles']}
l = {f['filePath']: f['content'] for f in live.get('additionalFiles') or []}
for f in sorted(set(w) | set(l)):
    s = 'new' if f not in l else 'REMOVED' if f not in w else 'same' if w[f] == l[f] else 'CHANGED'
    ok &= s == 'same'
    print(f'file {f}: {s}')
print('IDENTICAL' if ok else 'DIFFERENT')
PY
}

az rest -m GET --url "$url" --resource https://azuresre.dev > "$tmp/live.json" 2>/dev/null || : > "$tmp/live.json"
echo "-- live vs folder:"; compare "$tmp/live.json"
if [ "$apply" != "--apply" ]; then
  echo "dry run: nothing changed. Re-run with --apply to PUT $name."
  exit 0
fi
az rest -m PUT --url "$url" --resource https://azuresre.dev --headers Content-Type=application/json \
  --body @"$tmp/body.json" > /dev/null
az rest -m GET --url "$url" --resource https://azuresre.dev > "$tmp/after.json"
echo "-- after PUT, live vs folder:"; compare "$tmp/after.json"
