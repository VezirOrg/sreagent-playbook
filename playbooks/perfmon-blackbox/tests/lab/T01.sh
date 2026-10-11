#!/bin/sh
# T01: build the package and run the local compliance test on dc (authoring side, portable pwsh in C:\BbDev; P24, P25).
# Usage (repo root): direnv exec . playbooks/perfmon-blackbox/tests/run.sh T01 [dc]
set -eu
vm="${1:-dc}"; [ -n "$vm" ] || vm=dc; shift 2>/dev/null || true
here=$(cd "$(dirname "$0")" && pwd); pb=$(cd "$here/../.." && pwd); root=$(cd "$pb/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
(cd "$pb" && python3 -I -c "
import zipfile, os, sys
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:
    for top in ('package', 'tests/pester', 'tests/lab'):
        for d, _, fs in os.walk(top):
            for f in fs:
                if '/out' in d or f.endswith(('.pyc', '.sh')): continue
                z.write(os.path.join(d, f))
" "$tmp/src.zip")
lab="$root/.lab/perfmon-blackbox"
v() { (cd "$lab" && direnv exec "$root" scripts/vmssh "$@"); }
vscp() { (cd "$lab" && direnv exec "$root" scripts/vmscp "$@"); }
PWSH_URL='https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/PowerShell-7.4.6-win-x64.zip'
v "$vm" "New-Item -ItemType Directory -Force -Path C:\\BbDev | Out-Null; if (Test-Path C:\\BbDev\\src) { Remove-Item C:\\BbDev\\src -Recurse -Force }; if (-not (Test-Path C:\\BbDev\\pwsh\\pwsh.exe)) { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -UseBasicParsing '$PWSH_URL' -OutFile C:\\BbDev\\pwsh.zip; Expand-Archive C:\\BbDev\\pwsh.zip C:\\BbDev\\pwsh -Force }" >/dev/null 2>&1
vscp "$vm" "$tmp/src.zip" C:/BbDev/src.zip 2>/dev/null
v "$vm" "Expand-Archive C:\\BbDev\\src.zip C:\\BbDev\\src -Force; C:\\BbDev\\pwsh\\pwsh.exe -NoProfile -ExecutionPolicy Bypass -File C:\\BbDev\\src\\tests\\lab\\T01.ps1 $*" > "$tmp/out.txt" 2>&1 || true
grep -v '^direnv:' "$tmp/out.txt"
grep -q 'T01 RESULT: PASS' "$tmp/out.txt"
