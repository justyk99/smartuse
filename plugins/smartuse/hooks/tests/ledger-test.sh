#!/usr/bin/env bash
# Self-contained test for hooks/ledger.py: synthetic transcript + pending.json -> one ledger line; SubagentStop -> one receipt.
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj" "$HOME/.claude/smartuse/projects/proj"
T="$D/t.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:10Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:20Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0}}}' \
 '{"type":"assistant","timestamp":"2025-12-31T23:00:00Z","message":{"model":"m-b","usage":{"input_tokens":999,"output_tokens":999}}}' \
 '{"type":"user","timestamp":"2026-01-01T00:00:15Z","message":{}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:30Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:31Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:40Z","message":{"id":"grow","model":"m-a","usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":100}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:41Z","message":{"id":"grow","model":"m-a","usage":{"input_tokens":2,"output_tokens":900,"cache_read_input_tokens":100}}}' > "$T"
mkdir -p "$D/t/subagents"; printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:50Z","message":{"id":"sub1","model":"m-fork","usage":{"input_tokens":7,"output_tokens":70}}}' '{"type":"assistant","timestamp":"2025-12-31T00:00:00Z","message":{"id":"old","model":"m-fork","usage":{"input_tokens":1,"output_tokens":1}}}' > "$D/t/subagents/agent-x.jsonl"
echo '{"skill":"make-prompt","task":"t","mode":"quick","started_at":"2026-01-01T00:00:00Z","self_check":"13/13"}' > "$HOME/.claude/smartuse/projects/proj/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
L="$HOME/.claude/smartuse/ledger.jsonl"; [ -f "$L" ] || { echo "FAIL no ledger"; exit 1; }
python3 - "$L" <<'PY'
import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert r["total_output"]==100+5+900+70, r; assert r["total_input"]==100+100+2000+10+5+2+100+7, r; assert sorted(r["tokens"])==["m-a","m-fork"], r; assert r["assistant_calls"]==5
print("PASS stop: main + forked-subagent usage after started_at summed; earlier records ignored; shared id -> max")
PY
[ -f "$HOME/.claude/smartuse/projects/proj/pending.json" ] && { echo "FAIL pending not removed"; exit 1; } || echo "PASS pending removed"
echo '{"active":true}' > "$HOME/.claude/smartuse/projects/proj/routing.json"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a1\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
grep -q '"agent_id": "a1"' "$HOME/.claude/smartuse/projects/proj/receipts.jsonl" && echo "PASS subagent receipt written" || { echo "FAIL receipt"; exit 1; }
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a1\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
[ "$(grep -c '"agent_id": "a1"' "$HOME/.claude/smartuse/projects/proj/receipts.jsonl")" = 1 ] && echo "PASS second SubagentStop for the same agent -> no duplicate" || { echo "FAIL duplicate receipt"; exit 1; }
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
[ "$(wc -l < "$L")" = 1 ] && echo "PASS no pending -> no new line" || { echo "FAIL wrote without pending"; exit 1; }
# two Stop hooks at once (user-level + plugin copy) must produce ONE line
echo '{"skill":"make-prompt","task":"race","mode":"quick","started_at":"2026-01-01T00:00:00Z"}' > "$HOME/.claude/smartuse/projects/proj/pending.json"
IN="{\"hook_event_name\":\"Stop\",\"session_id\":\"s2\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}"
( echo "$IN" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" ) & ( echo "$IN" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" ) & wait
[ "$(grep -c '"task": "race"' "$L")" = 1 ] && echo "PASS concurrent hooks -> one line" || { echo "FAIL duplicate line from concurrent hooks"; exit 1; }
echo "ALL PASS"
