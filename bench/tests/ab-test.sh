#!/usr/bin/env bash
# Self-contained test for bench/ab.sh + bench/ab-report.py: a --dry-run through bench/fake-claude.sh (no model, no npm,
# nothing spent, temp HOME) must leave report.md with one row per (ask, dial), the "vs off" lines and a cheaper aggressive
# row. Exit 1 on failure.
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"; D=$(mktemp -d); export HOME="$D/home"; mkdir -p "$HOME"; OUT="$D/out"; fail=0
ok() { echo "PASS $1"; }; ko() { echo "FAIL $1"; fail=1; }
if CLAUDE_BIN="$B/fake-claude.sh" bash "$B/ab.sh" --dry-run --asks 2 --out "$OUT" > "$D/log.txt" 2>&1; then ok "ab.sh --dry-run --asks 2 exits 0"
else echo "FAIL ab.sh exited $? — log:"; cat "$D/log.txt"; exit 1; fi
grep -q "DRY RUN" "$D/log.txt" && ok "dry run announced, no spend NOTE" || ko "no DRY RUN line in the output"
R="$OUT/report.md"
[ -f "$R" ] && ok "report.md written" || { ko "report.md missing"; cat "$D/log.txt"; exit 1; }
for n in 1 2; do
  [ -s "$OUT/$n-stage1.json" ] && [ -s "$OUT/$n-meta.json" ] || ko "ask $n: stage1.json / meta.json missing"
  for d in off safe aggressive; do
    [ -s "$OUT/$n-$d.json" ] && [ -s "$OUT/$n-$d-receipts.json" ] || ko "ask $n $d: claude JSON or receipts missing"
    grep -q "\"dial\": \"$d\"" "$OUT/$n-$d-receipts.json" 2>/dev/null || ko "ask $n $d: receipts carry the wrong dial"
    [ -e "$OUT/$n-$d-npmtest.txt" ] && ko "ask $n $d: npm test ran in a dry run"
  done
done
[ -e "$OUT/3-meta.json" ] && ko "--asks 2 ran a third ask" || ok "raw files: 2 asks x (stage1 + 3 dials x (json + receipts)), --asks honoured, npm test skipped"
rows=$(grep -c -E '^\| [0-9]+ \| ' "$R"); [ "$rows" = 6 ] && ok "6 data rows (2 asks x 3 dials)" || ko "expected 6 data rows, got $rows"
grep -q -E 'safe vs off: agent out [-+]?[0-9]+% · cost [-+]?[0-9]+%' "$R" && ok "'safe vs off' line with percents" || ko "no 'safe vs off' line with a percent"
grep -q -E 'aggressive vs off: agent out [-+]?[0-9]+% · cost [-+]?[0-9]+%' "$R" && ok "'aggressive vs off' line with percents" || ko "no 'aggressive vs off' line with a percent"
python3 - "$R" <<'PY' && ok "aggressive row's agent out < off row's (ask 1)" || ko "aggressive row is not cheaper than off in the table"
import re, sys
col = {}
for l in open(sys.argv[1], encoding="utf-8"):
    if re.match(r"^\| 1 \| ", l):
        c = [x.strip() for x in l.strip().strip("|").split("|")]
        col[c[2]] = c[7]                      # dial -> agent out
def k(s):
    s = s.lstrip("~")
    return float(s[:-1]) * 1000 if s.endswith("k") else float(s)
assert "off" in col and "aggressive" in col, col
assert k(col["aggressive"]) < k(col["off"]), col
PY
grep -E '^\| 1 \| .* \| safe \| ' "$R" | grep -q '~' && ok "safe row marks the even split of a two-model step with ~" || ko "no ~ on the safe row's by-model cell"
grep -q 'split EVENLY' "$R" && ok "footnote explains the per-model split" || ko "footnote missing"
[ -z "$(ls -d "$HOME"/.claude/smartuse/projects/ab-* 2>/dev/null)" ] && ok "per-run state dirs removed after their receipts were copied" || ko "state dirs left under HOME"
[ -z "$(cd "$B/.." && git status --short -- bench/sample-repo 2>/dev/null)" ] && ok "fixture bench/sample-repo untouched" || ko "fixture modified"
rm -rf "$D"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
