#!/usr/bin/env bash
# A/B: routed vs not (the 0.4 roadmap item). Per ask in asks.txt: ONE kickoff (/smartuse:make-prompt quick) on a fresh,
# git-initialised copy of sample-repo/, a snapshot of that kickoff, then /smartuse:run-plan --until-done ONCE PER DIAL
# (off / safe / aggressive) on an identical restore of the snapshot, so the dials differ only in the routing.
# Collected per (ask, dial) under <out>/: claude's JSON (cost, turns, minutes, modelUsage), the per-step receipts the Stop hook
# archived (routing.json -> runs/ in the run dir's state dir, ~/.claude/smartuse/projects/<key>/ — found with the hooks' own rule,
# `ledger.py --state-dir` run inside the run dir, never guessed from its basename) and the `npm test` result.
# --model <id or alias> pins the session model of EVERY session (stage 1 and 2; passed to claude as --model, recorded in
# run.json). Without it claude's default decides per session, and A/B run 1 showed it can differ between the kickoff and the
# run-plan sessions, which makes the dials incomparable: pin it for a real run.
# bench/ab-report.py turns <out>/ into the comparison table. See README.md § "A/B: routed vs not".
# Writes nothing inside sample-repo/ or this repo except <out>/ (default bench/results/ab/, gitignored) and the dependency
# cache bench/.cache/node_modules. Every real session spends plan usage: read the NOTE this script prints. --dry-run spends nothing.
# The JSON work goes through python 3 and nothing else, found the way the hooks find it (plugins/smartuse/hooks/py.sh:
# python3, python or py -3, so Git Bash on Windows works).
set -u
export PYTHONUTF8=1   # every python below (and the hooks inside the nested claude runs) prints UTF-8, also on Windows pipes
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$HERE/../plugins/smartuse" 2>/dev/null && pwd || true)
PY="$HERE/../plugins/smartuse/hooks/py.sh"
ASKS_FILE="$HERE/asks.txt"
N_ASKS=0                       # 0 = every line of asks.txt
DIALS="off,safe,aggressive"
MODEL=""                       # "" = claude's default (not pinned)
OUT=""
DRY=0
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
# Caps per session, passed to claude -p and honoured by it. Stage 1 = make-prompt quick (once per ask), stage 2 = run-plan
# --until-done (once per dial). A run of N asks x M dials can never cost more than N x (S1_BUDGET + M x S2_BUDGET).
S1_TURNS=60; S1_BUDGET=4
S2_TURNS=40; S2_BUDGET=5

usage() { echo "usage: ab.sh [--asks N] [--dials off,safe,aggressive] [--model ID] [--plugin-dir P] [--out DIR] [--dry-run]"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --asks) N_ASKS=${2:-}; shift 2 ;;
    --dials) DIALS=${2:-}; shift 2 ;;
    --model) MODEL=${2:-}; [ -n "$MODEL" ] || { echo "--model needs a model id or alias (e.g. claude-opus-5-5, sonnet)" >&2; exit 2; }; shift 2 ;;
    --plugin-dir) PLUGIN_DIR=$(cd "${2:-}" 2>/dev/null && pwd || true); shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$N_ASKS" in ''|*[!0-9]*) echo "--asks takes a number" >&2; exit 2 ;; esac
[ -d "${PLUGIN_DIR:-}" ] || { echo "plugin dir not found; pass --plugin-dir" >&2; exit 2; }
for t in git tar; do command -v "$t" >/dev/null || { echo "$t is required" >&2; exit 2; }; done
[ -f "$PY" ] || { echo "python launcher not found: $PY (bench/ lives next to plugins/smartuse/ in the smartuse repo)" >&2; exit 2; }
py() { bash "$PY" "$@"; }       # the launcher prints nothing and exits 0 when no python runs, so probe its output
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "python 3 is required (none of python3, python, py -3 runs)" >&2; exit 2; }
IFS=, read -r -a DIAL_LIST <<< "$DIALS"
[ ${#DIAL_LIST[@]} -gt 0 ] || { echo "--dials needs at least one of off,safe,aggressive" >&2; exit 2; }
for d in "${DIAL_LIST[@]}"; do
  case "$d" in off|safe|aggressive) ;; *) echo "unknown dial: '$d' (off|safe|aggressive)" >&2; exit 2 ;; esac
done
# CLAUDE_BIN overrides the binary; the dry run points it at the shim unless the caller set it.
if [ "$DRY" = 1 ]; then CLAUDE_BIN=${CLAUDE_BIN:-$HERE/fake-claude.sh}; else CLAUDE_BIN=${CLAUDE_BIN:-claude}; fi
command -v "$CLAUDE_BIN" >/dev/null || { echo "claude binary not found: $CLAUDE_BIN (install claude or set CLAUDE_BIN)" >&2; exit 2; }
case "$CLAUDE_BIN" in */*) CLAUDE_BIN=$(cd "$(dirname "$CLAUDE_BIN")" && pwd)/$(basename "$CLAUDE_BIN") ;; esac   # the runs cd elsewhere
: "${HOME:?HOME is not set (the receipt state lives under ~/.claude/smartuse/projects/)}"
[ "$DRY" = 1 ] || command -v npm >/dev/null || { echo "npm is required (sample-repo needs its dependencies for npm test)" >&2; exit 2; }
[ -f "$ASKS_FILE" ] || { echo "asks file not found: $ASKS_FILE" >&2; exit 2; }
ASKS=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}            # a CRLF checkout (Windows) must not leak "\r" into the meta JSON and the report
  [ -z "$line" ] && continue
  ASKS+=("$line")
done < "$ASKS_FILE"
[ ${#ASKS[@]} -gt 0 ] || { echo "no asks in $ASKS_FILE" >&2; exit 2; }
if [ "$N_ASKS" -gt 0 ] && [ "$N_ASKS" -lt ${#ASKS[@]} ]; then ASKS=("${ASKS[@]:0:$N_ASKS}"); fi
N=${#ASKS[@]}; M=${#DIAL_LIST[@]}
[ -n "$OUT" ] || OUT="$HERE/results/ab/$TS"
mkdir -p "$OUT" || exit 2
OUT=$(cd "$OUT" && pwd)
VER=$("$CLAUDE_BIN" --version 2>/dev/null | head -1); VER=${VER:-unknown}

if [ "$DRY" = 1 ]; then
  echo "DRY RUN: $CLAUDE_BIN stands in for claude. No model is called, nothing is spent; npm install / npm test are skipped."
else
  echo "NOTE: every session below is a real Claude session and spends your plan usage."
  echo "      per ask: 1 make-prompt session (cap $S1_TURNS turns / \$$S1_BUDGET) + $M run-plan session(s) (cap $S2_TURNS turns / \$$S2_BUDGET each)."
  echo "      On the bench repo that is ~\$5-6 per ask per dial (kickoff ~\$1.5 once, each run-plan ~\$2-4 / 6 min)."
  echo "      Hard cap for this run: $N ask(s) x (\$$S1_BUDGET + $M x \$$S2_BUDGET) = \$$((N * (S1_BUDGET + M * S2_BUDGET))). Ctrl-C stops between sessions; --dry-run spends nothing."
  [ -n "$MODEL" ] || echo "      model: NOT pinned. claude's default decides per session and can differ between sessions (A/B run 1: kickoff on one model, run-plan on another); pass --model to pin it."
fi
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT   # the repo copies: $WORK/ab-<n>-<kickoff|dial>-<ts>, each removed after its session
MSHOW="claude's default (not pinned)"; [ -n "$MODEL" ] && MSHOW=$MODEL
echo "asks: $N · dials: $DIALS · model: $MSHOW · plugin: $PLUGIN_DIR · claude: $CLAUDE_BIN ($VER) · out: $OUT · work: $WORK"
py -c '
import json, sys
a = sys.argv[1:]
json.dump({"started_at": a[0], "dry_run": a[1] == "1", "asks": int(a[2]), "dials": a[3].split(","), "model": a[4] or None,
           "plugin_dir": a[5], "claude_bin": a[6], "claude_version": a[7],
           "caps": {"stage1": {"max_turns": int(a[8]), "max_budget_usd": int(a[9])},
                    "stage2": {"max_turns": int(a[10]), "max_budget_usd": int(a[11])}}}, sys.stdout, indent=2, ensure_ascii=False)
print()' "$TS" "$DRY" "$N" "$DIALS" "$MODEL" "$PLUGIN_DIR" "$CLAUDE_BIN" "$VER" "$S1_TURNS" "$S1_BUDGET" "$S2_TURNS" "$S2_BUDGET" > "$OUT/run.json"

CACHE="$HERE/.cache/node_modules"
STATE="$HOME/.claude/smartuse/projects"
state_dir_of() { # $1 = a repo copy -> the state dir the hooks used for it, by their own rule: ledger.py --state-dir of the plugin
  # under test, run inside the copy with CLAUDE_PROJECT_DIR unset (the way the nested claude ran). Keyed by the copy's full path
  # since hooks 0.4.0; the 0.3.0 basename dir only when the plugin cannot answer (an older plugin dir).
  local d; d=$(cd "$1" 2>/dev/null && env -u CLAUDE_PROJECT_DIR bash "$PLUGIN_DIR/hooks/py.sh" "$PLUGIN_DIR/hooks/ledger.py" --state-dir </dev/null 2>/dev/null)
  [ -n "$d" ] && echo "$d" || echo "$STATE/$(basename "$1")"
}
drop_state() { # $1 = a state dir from state_dir_of -> remove it; never anything outside $HOME/.claude/smartuse/projects/
  local d base; [ -d "$1" ] || return 0
  d=$(cd "$1" && pwd -P) && base=$(cd "$STATE" && pwd -P) || return 0
  case "$d/" in "$base/"?*) rm -rf "$d" ;; *) echo "  not removing $1: outside $STATE" >&2 ;; esac
}

summ() { # one line from a claude JSON file: $cost · turns · min · the models that ran (the keys of modelUsage)
  local s; s=$(py -c '
import json, math, sys
j = json.load(open(sys.argv[1], encoding="utf-8"))
def g(x): return str(int(x)) if x == int(x) else str(x)          # 2.0 -> "2", 1.55 -> "1.55"
def r(x): return math.floor(x + 0.5)                                # round half away from zero (non-negative input)
cost, turns, ms = float(j.get("total_cost_usd") or 0), j.get("num_turns") or 0, float(j.get("duration_ms") or 0)
mu = j.get("modelUsage"); models = "+".join(mu) if isinstance(mu, dict) else ""
print("$" + g(r(cost * 100) / 100) + " · " + str(turns) + " turns · " + g(r(ms / 60000 * 10) / 10) + " min" + (" · " + models if models else ""))' "$1" 2>/dev/null)
  [ -n "$s" ] && echo "$s" || echo "no JSON (see $(basename "$1" .json).err)"
}
meta_json() { # $1 = n, $2 = ask, $3 = task.md path or "" (-> null), $4 = note; the dials come from $DIALS
  py -c '
import json, sys
a = sys.argv[1:]
json.dump({"n": int(a[0]), "ask": a[1], "kickoff": a[2] or None, "note": a[3], "dials": a[4].split(",")}, sys.stdout, indent=2, ensure_ascii=False)
print()' "$1" "$2" "$3" "$4" "$DIALS"
}
install_deps() { # $1 = repo copy. Installed once, cached in bench/.cache/node_modules, reused with cp -a.
  if [ -d "$CACHE" ]; then
    cp -a "$CACHE" "$1/node_modules"
  else
    ( cd "$1" && npm install --no-audit --no-fund --loglevel=error ) || { echo "  npm install failed (npm test will fail; continuing)" >&2; return 1; }
    mkdir -p "$HERE/.cache" && cp -a "$1/node_modules" "$CACHE"
  fi
}
claude_run() { # $1 = cwd, $2 = prompt, $3 = max turns, $4 = max budget; stdout = claude's JSON. --model only when pinned.
  ( cd "$1" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_PROJECT_DIR "$CLAUDE_BIN" --plugin-dir "$PLUGIN_DIR" \
      ${MODEL:+--model "$MODEL"} \
      -p "$2" --permission-mode bypassPermissions --output-format json --max-turns "$3" --max-budget-usd "$4" )
}

n=0
for ask in "${ASKS[@]}"; do
  n=$((n+1))
  echo; echo "[$n/$N] $ask"
  # (a) fresh copy of the fixture, one commit, dependencies
  KICK="ab-$n-kickoff-$TS"; REPO="$WORK/$KICK"; mkdir -p "$REPO"
  cp -a "$HERE/sample-repo/." "$REPO/"
  ( cd "$REPO" && git init -q -b main && git add -A && git -c user.name=bench -c user.email=bench@example.invalid commit -q -m "bench fixture" ) \
    || echo "  warning: git init/commit failed in the copy" >&2
  [ "$DRY" = 1 ] || install_deps "$REPO"
  # (b) stage 1: the kickoff, ONCE per ask
  claude_run "$REPO" "/smartuse:make-prompt quick $ask" "$S1_TURNS" "$S1_BUDGET" > "$OUT/$n-stage1.json" 2> "$OUT/$n-stage1.err"
  echo "  stage 1 make-prompt quick: $(summ "$OUT/$n-stage1.json")"
  drop_state "$(state_dir_of "$REPO")"                     # the kickoff's receipt state (its ledger line is already written)
  TASK=$(cd "$REPO" && ls .task/ACTIVE/*/task.md 2>/dev/null | head -1)
  if [ -z "$TASK" ]; then
    echo "  no kickoff: stage 1 left no .task/ACTIVE/*/task.md; ask skipped (row: no kickoff)"
    meta_json "$n" "$ask" "" "no kickoff" > "$OUT/$n-meta.json"
    rm -rf "$REPO"; continue
  fi
  meta_json "$n" "$ask" "$TASK" "" > "$OUT/$n-meta.json"
  # (c) snapshot the kickoff so every dial starts from the same task.md
  SNAP="$WORK/ask-$n.tar"; tar -cf "$SNAP" -C "$REPO" . ; rm -rf "$REPO"
  # (d) stage 2: run-plan --until-done once per dial, each in a new dir of its own (its full path keys the receipt state the hooks write)
  for dial in "${DIAL_LIST[@]}"; do
    KEY="ab-$n-$dial-$TS"; D="$WORK/$KEY"; mkdir -p "$D"; tar -xf "$SNAP" -C "$D"
    claude_run "$D" "/smartuse:run-plan $TASK --until-done --routing $dial" "$S2_TURNS" "$S2_BUDGET" > "$OUT/$n-$dial.json" 2> "$OUT/$n-$dial.err"
    SD=$(state_dir_of "$D"); got=""                         # where the hooks archived the run (asked, not guessed)
    newest=$(ls -t "$SD/runs"/*.json 2>/dev/null | head -1)
    if [ -n "$newest" ]; then cp "$newest" "$OUT/$n-$dial-receipts.json"; got="receipts: runs/$(basename "$newest")"
    elif [ -f "$SD/routing.json" ]; then cp "$SD/routing.json" "$OUT/$n-$dial-receipts.json"; got="receipts: routing.json (run not closed)"
    fi
    if [ -n "$got" ]; then drop_state "$SD"; else got="no receipts (nothing in $SD)"; fi
    nt="npm test skipped (dry run)"
    if [ "$DRY" = 0 ]; then
      ( cd "$D" && npm test ) > "$OUT/$n-$dial-npmtest.txt" 2>&1; code=$?
      echo "npm test exit code: $code" >> "$OUT/$n-$dial-npmtest.txt"
      line=$(grep 'Tests:' "$OUT/$n-$dial-npmtest.txt" | head -1 | sed 's/^ *Tests: *//')
      nt="npm test: ${line:-exit code $code}"
    fi
    echo "  $dial: $(summ "$OUT/$n-$dial.json") · $got · $nt"
    rm -rf "$D"                                            # (e)
  done
  rm -f "$SNAP"
done

echo
py "$HERE/ab-report.py" "$OUT" || exit 1
echo
echo "raw files + report.md: $OUT"
