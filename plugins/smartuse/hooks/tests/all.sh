#!/usr/bin/env bash
# all.sh — run every smartuse regression suite and print ONE summary line, counted from the suites' PASS lines:
#   run N · ledger N · until-done N · file-guard N · heartbeat N · ab N
# run = bash-guard (run.sh) · ledger = ledger + receipts (ledger-test.sh) · until-done = the Stop gate · file-guard ·
# heartbeat · ab = bench/tests/ab-test.sh (the A/B runner's dry run through fake-claude.sh — spends nothing).
# The suites run in parallel (each makes its own temp HOME where it needs one), their output is printed in the fixed
# order above, and the summary is ALWAYS the last line, so `bash all.sh | tail -1` is the line the README quotes.
# A suite that exits non-zero, prints a FAIL line or no ALL PASS makes this script exit 1 after the summary.
# A FAIL line is "FAIL <check>" (one per failed check); the bare FAILURES line a failed suite ends with is not one, so it is not counted.
# Usage: bash plugins/smartuse/hooks/tests/all.sh        every suite's full output, then the summary
#        bash plugins/smartuse/hooks/tests/all.sh -q     only FAIL lines, one result line per suite, then the summary
T="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$T/../../../.." && pwd)"
quiet=0; [ "${1:-}" = "-q" ] && quiet=1
NAMES="run ledger until-done file-guard heartbeat ab"
script_of() { case "$1" in
  run) echo "$T/run.sh";; ledger) echo "$T/ledger-test.sh";; until-done) echo "$T/until-done-test.sh";;
  file-guard) echo "$T/file-guard-test.sh";; heartbeat) echo "$T/heartbeat-test.sh";; ab) echo "$ROOT/bench/tests/ab-test.sh";; esac; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
for n in $NAMES; do
  s=$(script_of "$n")
  if [ -f "$s" ]; then ( bash "$s" > "$W/$n.out" 2>&1; echo $? > "$W/$n.rc" ) & else { echo "missing: $s" > "$W/$n.out"; echo 127 > "$W/$n.rc"; }; fi
done
wait
summary=""; bad=0
for n in $NAMES; do
  out="$W/$n.out"; rc=$(cat "$W/$n.rc")
  pass=$(grep -c '^PASS' "$out"); fails=$(grep -c '^FAIL ' "$out")
  if [ "$quiet" = 1 ]; then grep '^FAIL ' "$out"; else cat "$out"; fi
  if [ "$rc" != 0 ] || [ "$fails" != 0 ] || ! grep -q '^ALL PASS' "$out"; then
    echo "== $n: FAILED (exit $rc · $pass PASS · $fails FAIL) — $(script_of "$n")"; bad=1
  else
    echo "== $n: $pass PASS"
  fi
  summary="$summary${summary:+ · }$n $pass"
done
echo "$summary"
[ "$bad" = 0 ] || exit 1
