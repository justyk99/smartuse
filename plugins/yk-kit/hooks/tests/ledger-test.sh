#!/usr/bin/env bash
# Self-contained test for hooks/ledger.py: synthetic transcript + pending.json -> one ledger line; SubagentStop -> one receipt.
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj/.claude/yk-kit"
T="$D/t.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:10Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:20Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0}}}' \
 '{"type":"assistant","timestamp":"2025-12-31T23:00:00Z","message":{"model":"m-b","usage":{"input_tokens":999,"output_tokens":999}}}' \
 '{"type":"user","timestamp":"2026-01-01T00:00:15Z","message":{}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:30Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:31Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' > "$T"
echo '{"skill":"make-prompt","task":"t","mode":"quick","started_at":"2026-01-01T00:00:00Z","self_check":"13/13"}' > "$D/proj/.claude/yk-kit/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
L="$HOME/.claude/yk-kit/ledger.jsonl"; [ -f "$L" ] || { echo "FAIL no ledger"; exit 1; }
python3 - "$L" <<'PY'
import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert r["total_output"]==105, r; assert r["total_input"]==100+100+2000+10+5, r; assert list(r["tokens"])==["m-a"], r; assert r["assistant_calls"]==3
print("PASS stop: calls after started_at summed, earlier record ignored, duplicate message id counted once")
PY
[ -f "$D/proj/.claude/yk-kit/pending.json" ] && { echo "FAIL pending not removed"; exit 1; } || echo "PASS pending removed"
echo '{"active":true}' > "$D/proj/.claude/yk-kit/routing.json"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a1\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
grep -q '"agent_id": "a1"' "$D/proj/.claude/yk-kit/receipts.jsonl" && echo "PASS subagent receipt written" || { echo "FAIL receipt"; exit 1; }
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
[ "$(wc -l < "$L")" = 1 ] && echo "PASS no pending -> no new line" || { echo "FAIL wrote without pending"; exit 1; }
echo "ALL PASS"
