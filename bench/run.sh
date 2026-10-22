#!/usr/bin/env bash
# Benchmark /smartuse:make-prompt (quick dry) over asks.txt. See README.md.
# The JSON cells come from python 3 and nothing else, found the way the hooks find it (plugins/smartuse/hooks/py.sh:
# python3, python or py -3, so Git Bash on Windows works).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$HERE/../plugins/smartuse" 2>/dev/null && pwd || true)
PY="$HERE/../plugins/smartuse/hooks/py.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-dir) PLUGIN_DIR=$(cd "$2" && pwd); shift 2 ;;
    -h|--help) echo "usage: run.sh [--plugin-dir <path>]"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[ -d "${PLUGIN_DIR:-}" ] || { echo "plugin dir not found; pass --plugin-dir" >&2; exit 2; }
[ -f "$PY" ] || { echo "python launcher not found: $PY (bench/ lives next to plugins/smartuse/ in the smartuse repo)" >&2; exit 2; }
py() { bash "$PY" "$@"; }       # the launcher prints nothing and exits 0 when no python runs, so probe its output
[ "$(py -c 'print("ok")' </dev/null 2>/dev/null)" = ok ] || { echo "python 3 is required (none of python3, python, py -3 runs)" >&2; exit 2; }

echo "NOTE: each run is a real Claude session (up to 60 turns, \$4 cap) and spends your plan usage."

RESULTS="$HERE/results"; mkdir -p "$RESULTS"
n=0; ROWS=""
while IFS= read -r ask || [ -n "$ask" ]; do
  [ -z "$ask" ] && continue
  n=$((n+1))
  TMP=$(mktemp -d)
  cp -a "$HERE/sample-repo/." "$TMP/"
  ( cd "$TMP" && git init -q )
  echo "[$n] $ask"
  ( cd "$TMP" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --plugin-dir "$PLUGIN_DIR" \
      -p "/smartuse:make-prompt quick dry $ask" \
      --permission-mode bypassPermissions --output-format json \
      --max-turns 60 --max-budget-usd 4 ) > "$RESULTS/$n.json" 2> "$RESULTS/$n.err"
  rm -rf "$TMP"
  f="$RESULTS/$n.json"
  # the five cells from claude's JSON, tab-separated: cost · turns · minutes · prompt saved · self-check (n/a, no when unreadable)
  IFS=$'\t' read -r cost turns mins saved check < <(py -c '
import json, math, re, sys
try:
    j = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    j = {}
def g(x): return str(int(x)) if x == int(x) else str(x)           # 1.0 -> "1", 2.4 -> "2.4"
cost, turns, ms, result = j.get("total_cost_usd"), j.get("num_turns"), j.get("duration_ms"), j.get("result")
result = result if isinstance(result, str) else ""
print("\t".join(["n/a" if cost is None else str(cost), "n/a" if turns is None else str(turns),
                 "n/a" if not ms else g(math.floor(ms / 60000 * 10 + 0.5) / 10),
                 "yes" if re.search(r"prompt saved|kickoff prompt is saved|saved (at|to)", result, re.I) else "no",
                 "yes" if re.search(r"self-check", result, re.I) else "no"]))' "$f" 2>/dev/null || printf 'n/a\tn/a\tn/a\tno\tno\n')
  ROWS="$ROWS| $ask | $cost | $turns | $mins | $saved | $check |"$'\n'
done < "$HERE/asks.txt"

echo
echo "| Ask | Cost (USD) | Turns | Minutes | Prompt saved | Self-check |"
echo "|---|---|---|---|---|---|"
printf '%s' "$ROWS"
echo
echo "Claude Code version: $(claude --version 2>/dev/null || echo unknown)"
