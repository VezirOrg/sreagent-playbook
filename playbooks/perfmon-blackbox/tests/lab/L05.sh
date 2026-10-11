#!/bin/sh
# L05: copy the package and the Pester tests to C:\BbDev on a lab VM and run tests/pester/Run-L05.ps1 there under
# Windows PowerShell 5.1 (P24, P25). Run from the repo root: direnv exec . playbooks/perfmon-blackbox/tests/run.sh L05 [vm]
# Never touches the running collectors or C:\ProgramData\PerfmonBlackbox. Extra args go to Run-L05.ps1 (-Clean, -LintOnly).
set -eu
vm="${1:-dc}"; shift 2>/dev/null || true
here=$(cd "$(dirname "$0")" && pwd); pb=$(cd "$here/../.." && pwd); root=$(cd "$pb/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
(cd "$pb" && python3 -I -c "
import zipfile, os, sys
with zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED) as z:
    for top in ('package', 'tests/pester'):
        for d, _, fs in os.walk(top):
            for f in fs:
                if '/out/' in d + '/' or f.endswith('.pyc'): continue
                z.write(os.path.join(d, f))
" "$tmp/src.zip")
lab="$root/.lab/perfmon-blackbox"
v() { (cd "$lab" && direnv exec "$root" scripts/vmssh "$@"); }
vscp() { (cd "$lab" && direnv exec "$root" scripts/vmscp "$@"); }
v "$vm" "New-Item -ItemType Directory -Force -Path C:\\BbDev | Out-Null; if (Test-Path C:\\BbDev\\src) { Remove-Item C:\\BbDev\\src -Recurse -Force }" >/dev/null 2>&1
vscp "$vm" "$tmp/src.zip" C:/BbDev/src.zip 2>/dev/null
v "$vm" "Expand-Archive C:\\BbDev\\src.zip C:\\BbDev\\src -Force; powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\BbDev\\src\\tests\\pester\\Run-L05.ps1 $*" > "$tmp/out.txt" 2>&1 || true
grep -v '^direnv:' "$tmp/out.txt"
grep -q 'L05 RESULT: PASS' "$tmp/out.txt"
