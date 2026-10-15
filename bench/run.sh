#!/usr/bin/env bash
# Benchmark /yk-kit:make-prompt (quick dry) over asks.txt. See README.md.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$HERE/../plugins/yk-kit" 2>/dev/null && pwd || true)

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin-dir) PLUGIN_DIR=$(cd "$2" && pwd); shift 2 ;;
    -h|--help) echo "usage: run.sh [--plugin-dir <path>]"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
[ -d "${PLUGIN_DIR:-}" ] || { echo "plugin dir not found; pass --plugin-dir" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

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
      -p "/yk-kit:make-prompt quick dry $ask" \
      --permission-mode bypassPermissions --output-format json \
      --max-turns 60 --max-budget-usd 4 ) > "$RESULTS/$n.json" 2> "$RESULTS/$n.err"
  rm -rf "$TMP"
  f="$RESULTS/$n.json"
  cost=$(jq -r '.total_cost_usd // "n/a"' "$f" 2>/dev/null || echo n/a)
  turns=$(jq -r '.num_turns // "n/a"' "$f" 2>/dev/null || echo n/a)
  mins=$(jq -r 'if .duration_ms then (.duration_ms/60000*10|round/10|tostring) else "n/a" end' "$f" 2>/dev/null || echo n/a)
  saved=no; jq -r '.result // ""' "$f" 2>/dev/null | grep -q "Prompt saved" && saved=yes
  check=no;  jq -r '.result // ""' "$f" 2>/dev/null | grep -q "✓" && check=yes
  ROWS="$ROWS| $ask | $cost | $turns | $mins | $saved | $check |"$'\n'
done < "$HERE/asks.txt"

echo
echo "| Ask | Cost (USD) | Turns | Minutes | Prompt saved | Self-check |"
echo "|---|---|---|---|---|---|"
printf '%s' "$ROWS"
echo
echo "Claude Code version: $(claude --version 2>/dev/null || echo unknown)"
