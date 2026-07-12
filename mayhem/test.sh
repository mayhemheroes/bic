#!/usr/bin/env bash
#
# mayhem/test.sh — RUN bic's upstream functional test suite (already built by mayhem/build.sh
# into $SRC/build-tests). The suite is a differential/known-answer oracle: each testsuite/*.c
# is compiled with the native cc AND executed by the bic interpreter (`bic -s file.c`), and the
# two outputs must match; the *.exp cases drive the REPL under `expect`. So a sabotage patch that
# makes bic exit(0) / produce no output FAILS here (outputs diverge). We only RUN + parse here.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TDIR="$SRC/build-tests"
if [ ! -f "$TDIR/src/bic" ]; then
  echo "test.sh: build-tests/src/bic missing — mayhem/build.sh did not build the suite" >&2
  emit_ctrf "automake-check" 0 1 0
  exit 1
fi

log="$(mktemp)"
( cd "$TDIR" && make -j"$MAYHEM_JOBS" check ) 2>&1 | tee "$log" || true

# Parse the automake test-harness summary ("# PASS:", "# FAIL:", ...).
sumfile="$TDIR/testsuite/test-suite.log"
grab() { grep -aE "^# $1:" "$log" | tail -1 | grep -aoE '[0-9]+' | tail -1; }
PASS=$(grab PASS);  FAIL=$(grab FAIL);  SKIP=$(grab SKIP)
XFAIL=$(grab XFAIL); XPASS=$(grab XPASS); ERROR=$(grab ERROR)
PASS=${PASS:-0}; FAIL=${FAIL:-0}; SKIP=${SKIP:-0}
XFAIL=${XFAIL:-0}; XPASS=${XPASS:-0}; ERROR=${ERROR:-0}

# XPASS (unexpected pass) and ERROR count as failures; XFAIL (expected fail) as skipped.
failed=$(( FAIL + XPASS + ERROR ))
skipped=$(( SKIP + XFAIL ))

if [ "$(( PASS + failed ))" -eq 0 ]; then
  echo "test.sh: no test results parsed from 'make check'" >&2
  [ -f "$sumfile" ] && tail -40 "$sumfile" >&2
  rm -f "$log"; emit_ctrf "automake-check" 0 1 0; exit 1
fi

rm -f "$log"
emit_ctrf "automake-check" "$PASS" "$failed" "$skipped"
