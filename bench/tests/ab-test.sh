#!/usr/bin/env bash
# Self-contained test for bench/ab.sh + bench/ab-report.py: --dry-run through bench/fake-claude.sh (no model, no npm, no
# JSON tool beyond python, nothing spent, temp HOME). Run A (--model pinned, 2 asks): one row per (ask, dial), the session-model column, the "vs off"
# lines with percents, a cheaper aggressive row, the exact per-model split (no ~) from agent_by_model, and ask 2's `off` row
# (the shim stops it on NEEDS YOU before any step) marked "no work done", kept out of the deltas and the medians. Run B (no
# --model, 1 ask): the shim drifts between the stages the way A/B run 1 did and the report flags it. Run C: the report over a
# copy of run A's files with agent_by_model stripped (an archive from before hooks 0.4.0) falls back to the even split marked ~.
# Run A also checks the state dirs: each run dir's state dir is the one `ledger.py --state-dir` names for it (keyed by the full
# path, not the basename) and is gone once its receipts were copied; fake-claude.sh is run on its own to show it archives there.
# Python runs through the plugin's launcher (plugins/smartuse/hooks/py.sh), like the hooks and ab.sh. Exit 1 on failure.
set -u
B="$(cd "$(dirname "$0")/.." && pwd)"; PLUG="$B/../plugins/smartuse"; PY="$PLUG/hooks/py.sh"; LEDGER="$PLUG/hooks/ledger.py"; D=$(mktemp -d); export HOME="$D/home"; mkdir -p "$HOME"; OUT="$D/out"; fail=0
ok() { echo "PASS $1"; }; ko() { echo "FAIL $1"; fail=1; }
py() { bash "$PY" "$@"; }
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "FAIL no python 3 (python3, python or py -3) through $PY"; exit 1; }

# --- run A: 2 asks x 3 dials, the session model pinned
if CLAUDE_BIN="$B/fake-claude.sh" bash "$B/ab.sh" --dry-run --asks 2 --model claude-test-9-9 --out "$OUT" > "$D/log.txt" 2>&1; then ok "ab.sh --dry-run --asks 2 --model claude-test-9-9 exits 0"
else echo "FAIL ab.sh exited $? — log:"; cat "$D/log.txt"; exit 1; fi
grep -q "DRY RUN" "$D/log.txt" && ok "dry run announced, no spend NOTE" || ko "no DRY RUN line in the output"
grep -q "model: claude-test-9-9" "$D/log.txt" && ok "the pinned model is announced" || ko "no 'model: claude-test-9-9' in the output"
grep -q "stage 1 make-prompt quick: \$1.5 · 6 turns · 2.5 min · claude-test-9-9" "$D/log.txt" && ok "progress line: cost · turns · min · the models that ran" || ko "stage 1 progress line wrong or missing"
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
bad=0; for f in "$OUT"/*.json; do py -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null || { bad=1; echo "  unparseable: $f"; }; done
[ $bad = 0 ] && ok "every JSON file parses (claude JSON, receipts, meta, run.json)" || ko "a JSON file does not parse"
grep -q '"model": "claude-test-9-9"' "$OUT/run.json" && ok "run.json records the pinned model" || ko "run.json lacks \"model\": \"claude-test-9-9\""
grep -q '"modelUsage"' "$OUT/1-stage1.json" && grep -q '"agent_by_model"' "$OUT/1-safe-receipts.json" && ok "shim writes modelUsage and agent_by_model" || ko "shim output lacks modelUsage / agent_by_model"
rows=$(grep -c -E '^\| [0-9]+ \| ' "$R"); [ "$rows" = 6 ] && ok "6 data rows (2 asks x 3 dials)" || ko "expected 6 data rows, got $rows"
grep -q '| session model |' "$R" && ok "session model column present" || ko "no 'session model' column"
grep -q 'model: claude-test-9-9 (pinned with --model)' "$R" && ok "header says the model is pinned" || ko "header does not say 'pinned with --model'"
grep -q -E '^- \*\*1 · .*kickoff \$1\.50 · 2\.5 min · 6 turns · on test-9-9 · `\.task/ACTIVE/csv-export/task\.md`' "$R" && ok "per-ask line shows the kickoff's model and task.md" || ko "kickoff line lacks 'on test-9-9' / the task.md path"
grep -q -E '^  - \*\*models differ\*\*' "$R" && ko "'models differ' flagged although --model pinned every session" || ok "no 'models differ' flag with --model (the footnote only explains it)"
grep -q -E '^  - safe vs off: agent out [-+]?[0-9]+% · cost [-+]?[0-9]+%' "$R" && ok "'safe vs off' line with percents (ask 1)" || ko "no 'safe vs off' line with a percent"
grep -q -E '^  - aggressive vs off: agent out [-+]?[0-9]+% · cost [-+]?[0-9]+%' "$R" && ok "'aggressive vs off' line with percents (ask 1)" || ko "no 'aggressive vs off' line with a percent"
grep -q -E '^  - safe vs off: off did no work → no comparison$' "$R" && grep -q -E '^  - aggressive vs off: off did no work → no comparison$' "$R" \
  && ok "ask 2: 'off did no work → no comparison' instead of a percent" || ko "no 'off did no work → no comparison' lines for ask 2"
[ "$(grep -c -E 'vs off: agent out [-+]?[0-9]+%' "$R")" = 2 ] && ok "exactly 2 percent lines (ask 1 only)" || ko "percent lines other than ask 1's"
grep -q -E '^- \*\*off\*\*: agent out 9\.0k · cost \$3\.70 .*\(n=1; 1 excluded: no work done\)' "$R" && ok "off median over ask 1 only; 1 row excluded and counted" || ko "off median line does not exclude/count the no-work row"
grep -q -E '^- \*\*safe\*\*: .*\(n=2\) · vs off \(median of the per-ask deltas, 1 compared\): agent out -11% · cost -8%' "$R" && ok "safe median: n=2, delta from the 1 compared ask" || ko "safe median line wrong"
grep -q -E '^- \*\*aggressive\*\*: .*\(n=2\) · vs off \(median of the per-ask deltas, 1 compared\): agent out -33% · cost -43%' "$R" && ok "aggressive median: n=2, delta from the 1 compared ask" || ko "aggressive median line wrong"
py - "$R" <<'PY' && ok "table cells: session models, exact split without ~ (agent_by_model), aggressive < off, ask 2 off = no work (—)" || ko "table cell check failed (see above)"
import re, sys
rows = {}
for l in open(sys.argv[1], encoding="utf-8"):
    if re.match(r"^\| \d+ \| ", l):
        c = [x.strip() for x in l.strip().strip("|").split("|")]
        rows[(c[0], c[2])] = c   # 0 n · 1 ask · 2 dial · 3 session model · 4 steps · 5 needs_human · 6 npm · 7 by model · 8 agent out · 9 cost · 10 min · 11 turns · 12 note
def k(s):
    s = s.lstrip("~")
    return float(s[:-1]) * 1000 if s.endswith("k") else float(s)
r1o, r1s, r1a, r2o, r2s = rows[("1", "off")], rows[("1", "safe")], rows[("1", "aggressive")], rows[("2", "off")], rows[("2", "safe")]
assert r1o[3] == "test-9-9", r1o[3]
assert r1s[3] == "test-9-9 (+sonnet-5-5, haiku-5-5)", r1s[3]
assert "~" not in r1s[7] and "~" not in r1a[7], (r1s[7], r1a[7])
assert r1s[7] == "haiku-5-5 3.5k · test-9-9 3.0k · sonnet-5-5 1.5k", r1s[7]   # the hook's own per-model numbers, not 4.5k split in two
assert k(r1a[8]) < k(r1o[8]), (r1a[8], r1o[8])
assert r2o[4] == "0/4/0" and r2o[5] == "yes", r2o
assert r2o[7] == "—" and r2o[8] == "—", (r2o[7], r2o[8])
assert r2o[12] == "no work done — stopped on NEEDS YOU before any step", r2o[12]
assert r2s[8] == "8.0k" and r2s[12] == "", r2s
PY
grep -q 'agent_by_model' "$R" && grep -q 'split EVENLY' "$R" && ok "footnote explains the exact split and the ~ fallback" || ko "footnote missing agent_by_model / split EVENLY"
# the per-run state dirs follow the hooks' own rule (ledger.py --state-dir: keyed by the run dir's full path, not its basename);
# ab.sh located each one the same way and removed it after copying the receipts. The run dirs were $work/ab-<n>-<dial>-<ts>
# (work from the header line, ts = run.json started_at), so compute their state dirs back and check none is left.
WORKD=$(sed -n 's/.* · work: //p' "$D/log.txt" | head -1); TS=$(py -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["started_at"])' "$OUT/run.json")
[ -n "$WORKD" ] && [ -n "$TS" ] && ok "header names the work dir, run.json the timestamp (the run dirs were \$work/ab-<n>-<dial>-<ts>)" || ko "cannot rebuild the run dir paths (work: '$WORKD', ts: '$TS')"
chk=$(for n in 1 2; do for d in kickoff off safe aggressive; do
  printf '%s\t%s\n' "ab-$n-$d-$TS" "$(CLAUDE_PROJECT_DIR="$WORKD/ab-$n-$d-$TS" py "$LEDGER" --state-dir)"; done; done | py -c '
import os, pathlib, sys
base = (pathlib.Path(os.environ["HOME"]) / ".claude" / "smartuse" / "projects").resolve()
bad = []
for l in sys.stdin.read().splitlines():
    name, sd = l.split("\t", 1); p = pathlib.Path(sd)
    if not sd: bad.append(name + ": --state-dir printed nothing")
    elif p.resolve().parent != base: bad.append(name + ": " + sd + " is not directly under " + str(base))
    elif p.name == name: bad.append(name + ": keyed by the basename, not the full path")
    elif p.exists(): bad.append(name + ": state dir left behind: " + sd)
print("; ".join(bad))')
[ -z "$chk" ] && ok "per-run state dirs: keyed under projects/ by the full path (8 of 8, ledger.py --state-dir) and removed after their receipts were copied" || ko "state dirs: $chk"
[ -z "$(ls -d "$HOME"/.claude/smartuse/projects/ab-* 2>/dev/null)" ] && ok "no projects/<basename> dirs either (nothing fell back to the 0.3.0 rule)" || ko "basename-keyed state dirs left under HOME"
# fake-claude.sh on its own: the archive lands in the dir ledger.py --state-dir prints for its cwd, not under projects/<basename>
X="$D/x/ab-9-safe-T"; mkdir -p "$X"; printf '# task\n' > "$X/task.md"
( cd "$X" && env -u CLAUDE_PROJECT_DIR bash "$B/fake-claude.sh" --plugin-dir "$PLUG" -p "/smartuse:run-plan task.md --until-done --routing safe" ) > /dev/null 2>&1
sd=$(cd "$X" && env -u CLAUDE_PROJECT_DIR bash "$PY" "$LEDGER" --state-dir)
[ -f "$sd/runs/2026-01-01T00-00-00Z_csv-export.json" ] && [ ! -d "$HOME/.claude/smartuse/projects/ab-9-safe-T" ] && ok "fake-claude.sh archives into the keyed state dir (ledger.py --state-dir), not projects/<basename>" || ko "fake-claude.sh archive not in $sd/runs/ (basename dir exists: $([ -d "$HOME/.claude/smartuse/projects/ab-9-safe-T" ] && echo yes || echo no))"
[ -z "$(cd "$B/.." && git status --short -- bench/sample-repo 2>/dev/null)" ] && ok "fixture bench/sample-repo untouched" || ko "fixture modified"

# --- run B: no --model: the shim drifts between the stages (kickoff fable-5-1, run-plan opus-5-5) and the report says so
OUT2="$D/out2"
if CLAUDE_BIN="$B/fake-claude.sh" bash "$B/ab.sh" --dry-run --asks 1 --out "$OUT2" > "$D/log2.txt" 2>&1; then ok "ab.sh --dry-run --asks 1 (no --model) exits 0"
else echo "FAIL ab.sh (run B) exited $? — log:"; cat "$D/log2.txt"; exit 1; fi
grep -q '"model": null' "$OUT2/run.json" && ok "run.json: model null when not pinned" || ko "run.json lacks \"model\": null"
grep -q 'model: not pinned' "$OUT2/report.md" && ok "header says the model is not pinned" || ko "header does not say 'not pinned'"
grep -q -E '^  - \*\*models differ\*\* \(kickoff on fable-5-1, off on opus-5-5, safe on opus-5-5, aggressive on opus-5-5\)' "$OUT2/report.md" \
  && ok "'models differ' flagged: kickoff on fable-5-1, run-plan sessions on opus-5-5" || ko "no 'models differ' line for the drifted run"
grep -q -E '^\| 1 \| .* \| off \| opus-5-5 \| ' "$OUT2/report.md" && ok "session model column: opus-5-5 from modelUsage" || ko "off row lacks opus-5-5"

# --- run C: an archive from before agent_by_model (strip it from run A's receipts) -> even split marked ~
OLD="$D/old"; cp -a "$OUT" "$OLD"
py - "$OLD" <<'PY'
import glob, json, os, sys
for f in glob.glob(os.path.join(sys.argv[1], "*-receipts.json")):
    r = json.load(open(f, encoding="utf-8"))
    for u in r.get("units", []):
        u.pop("agent_by_model", None)
    json.dump(r, open(f, "w", encoding="utf-8"), indent=2)
PY
py "$B/ab-report.py" "$OLD" > /dev/null 2>&1 && ok "report over an archive without agent_by_model exits 0" || ko "ab-report.py failed on the stripped archive"
grep -E '^\| 1 \| .* \| safe \| ' "$OLD/report.md" | grep -q '~' && ok "safe row falls back to the even split marked ~ (two-model step)" || ko "no ~ on the stripped safe row"
grep -E '^\| 1 \| .* \| aggressive \| ' "$OLD/report.md" | grep -q '~' && ko "aggressive row (single-model steps) marked ~" || ok "single-model steps stay exact without agent_by_model"
rm -rf "$D"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
