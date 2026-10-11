#!/bin/sh
# tests/run.sh <ID|all> [machine] [--keep-going]: one command per test (test plan). Prints PASS/FAIL <ID>.
#   Local tests (no Azure, synthetic data): L01 L02 L03 L04 L06 L07 (L05 = Pester, on a lab VM: tests/run.sh L05 dc)
#   Lab tests T01..T16: tests/lab/<ID>.sh [machine], run from the repo root via direnv (see docs/test-plan.md).
set -u
here=$(cd "$(dirname "$0")" && pwd)
pb=$(cd "$here/.." && pwd)
root=$(cd "$pb/../.." && pwd)
id="${1:?usage: tests/run.sh <ID|all> [machine] [--keep-going]}"; shift
machine=""; keep=0
for a in "$@"; do case "$a" in --keep-going) keep=1 ;; *) machine="$a" ;; esac; done

local_test() {  # $1 = L0x
  case "$1" in
    L01) cls=L01Converter ;; L02) cls=L02Perfq ;; L03) cls=L03Masker ;; L04) cls=L04FetchLatest ;; L07) cls=L07Template ;; L08) cls=L08Policies ;;
    L06) (cd "$root" && scripts/scrub-check.sh --self-test >/dev/null && scripts/scrub-check.sh); return $? ;;
    L05) sh "$here/lab/L05.sh" "${machine:-dc}"; return $? ;;
    *) echo "unknown test $1" >&2; return 2 ;;
  esac
  (cd "$pb" && python3 -m unittest "tests.local.test_local.$cls" 2>&1 | tail -3)
}

one() {
  case "$1" in
    L0*) local_test "$1" ;;
    T*) [ -f "$here/lab/$1.sh" ] || { echo "no lab script for $1 yet"; return 2; }; sh "$here/lab/$1.sh" "$machine" ;;
    *) echo "unknown test $1" >&2; return 2 ;;
  esac
  rc=$?
  if [ $rc -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fi
  return $rc
}

if [ "$id" = all ] || [ "$id" = local ]; then
  ids="L01 L02 L03 L04 L06 L07 L08"
  [ "$id" = all ] && ids="$ids T13 T14 T01 T02 T03 T04 T05 T06 T07 T06b T06c T07b T08 T09 T10 T10b T10c T11 T12 T15 T16"
  fail=0
  for t in $ids; do one "$t" || { fail=1; [ $keep -eq 1 ] || exit 1; }; done
  exit $fail
fi
one "$id"
