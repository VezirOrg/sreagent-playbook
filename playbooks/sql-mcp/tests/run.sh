#!/bin/sh
# tests/run.sh <ID|local>: one command per test. Prints PASS/FAIL/SKIP <ID>.
#   Local (no Azure, synthetic values): L01 config generator, L02 PowerShell 5.1 lint, L03 package, L04 DAB drift.
#   L01 and L02 need PowerShell 7 on this machine (`pwsh` on the PATH, or $PWSH). L04 reads the GitHub API.
#   Lab tests T10..T25: tests/lab/<ID>.sh, run from the repo root (docs/tests.md).
set -u
here=$(cd "$(dirname "$0")" && pwd)
pb=$(cd "$here/.." && pwd)
id="${1:?usage: tests/run.sh <ID|local>}"
ps=${PWSH:-$(command -v pwsh || true)}

one() {
  case "$1" in
    L01) out=$(cd "$pb" && python3 -m unittest -v tests.local.test_local.L01DabConfig 2>&1); rc=$?
         echo "$out" | tail -3; echo "$out" | grep -q 'skipped' && { echo "SKIP $1 (no pwsh)"; return 0; } ;;
    L02) [ -n "$ps" ] || { echo "SKIP $1 (no pwsh)"; return 0; }
         "$ps" -NoProfile -NonInteractive -File "$here/local/lint.ps1" -Src "$pb"; rc=$? ;;
    L03) out=$(cd "$pb" && python3 -m unittest tests.local.test_local.L03Package 2>&1); rc=$?; echo "$out" | tail -3 ;;
    L04) sh "$here/local/dab-drift.sh"; rc=$? ;;
    T*) [ -f "$here/lab/$1.sh" ] || { echo "no lab script for $1 yet"; return 2; }; sh "$here/lab/$1.sh"; rc=$? ;;
    *) echo "unknown test $1" >&2; return 2 ;;
  esac
  if [ $rc -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fi
  return $rc
}

if [ "$id" = local ]; then
  fail=0; for t in L01 L02 L03 L04; do one $t || fail=1; done; exit $fail
fi
one "$id"
