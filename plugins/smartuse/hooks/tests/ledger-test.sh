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
echo '{"skill":"living-docs","task":"future","mode":"update","started_at":"2099-01-01T00:00:00Z"}' > "$HOME/.claude/smartuse/projects/proj/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s3\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
python3 - "$L" <<'PY'
import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1]); assert r["task"]=="future" and 840 <= r["duration_s"] <= 960 and "future" in (r.get("notes") or ""), r
print("PASS future started_at -> 15-minute window, note added")
PY
# two Stop hooks at once (user-level + plugin copy) must produce ONE line
echo '{"skill":"make-prompt","task":"race","mode":"quick","started_at":"2026-01-01T00:00:00Z"}' > "$HOME/.claude/smartuse/projects/proj/pending.json"
IN="{\"hook_event_name\":\"Stop\",\"session_id\":\"s2\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}"
( echo "$IN" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" ) & ( echo "$IN" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" ) & wait
[ "$(grep -c '"task": "race"' "$L")" = 1 ] && echo "PASS concurrent hooks -> one line" || { echo "FAIL duplicate line from concurrent hooks"; exit 1; }
# --- receipt per plan step: the agent's tokens land on the unit that is "running" in routing.json
P="$HOME/.claude/smartuse/projects/proj"
echo '{"active":true,"task":"csv-export","dial":"safe","started_at":"2026-01-01T00:00:00Z","until_done":true,"units":[{"id":1,"title":"decide","tier":"judgment","model":"session","status":"pass"},{"id":2,"title":"build route","tier":"build","model":"opus","why":"has a test","status":"running","check":"npm test"},{"id":3,"title":"tests","tier":"build","model":"opus","status":"pending"}]}' > "$P/routing.json"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"b1\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
python3 - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); u=r["units"][1]
assert u["agent_calls"]==5 and u["agent_output"]==2004 and u["agent_input"]==3316 and u["agents"]==["b1"] and u["agent_models"]==["m-a","m-b"], u
assert r["units"][0].get("agent_output") is None and r["units"][2].get("agent_output") is None
line=json.loads(open(P/"receipts.jsonl").read().splitlines()[-1]); assert line["agent_id"]=="b1" and line["unit"]==2, line
print("PASS SubagentStop -> tokens attached to the running step (unit 2), receipt line carries unit")
PY
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"b2\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
python3 - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); u=json.load(open(P/"routing.json"))["units"][1]
assert u["agent_calls"]==10 and u["agent_output"]==4008 and u["agents"]==["b1","b2"], u
print("PASS second agent on the same step (verify) accumulates")
PY
python3 - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); r["units"][2]["status"]="running"; json.dump(r,open(P/"routing.json","w"))
PY
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"c1\",\"agent_transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
python3 - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json"))
assert r["units"][1]["agent_calls"]==10 and r["units"][2].get("agent_calls") is None, r
line=json.loads(open(P/"receipts.jsonl").read().splitlines()[-1]); assert line["agent_id"]=="c1" and line["unit"] is None, line
print("PASS two running steps -> receipt stays unattached, nothing guessed")
PY
python3 - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); r["units"][1]["status"]="pass"; r["units"][1]["verify"]="no gaps"; r["units"][2]["status"]="blocked"; r["units"][2]["override"]={"from":"mechanical","to":"build","by":"user"}; json.dump(r,open(P/"routing.json","w"))
PY
OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" --receipts)
echo "$OUT" | grep -q "| 2 | build route | build | opus |  | pass |  | no gaps | 10 | 6.6k | 4.0k | npm test |" && echo "$OUT" | grep -q "| 3 | tests | build | opus | mechanical→build | blocked |" && echo "$OUT" | grep -q "steps 2 pass · 1 blocked · 0 open" && echo "PASS --receipts: one row per plan step with tier, model, override, outcome, verify, tokens" || { echo "FAIL --receipts output:"; echo "$OUT"; exit 1; }
# run-plan close -> the Stop hook archives routing.json under runs/ so /smartuse:receipts <task> finds it later
echo '{"skill":"run-plan","task":"csv-export","mode":"safe","started_at":"2026-01-01T00:00:00Z","self_check":"2/3"}' > "$P/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s4\",\"transcript_path\":\"$T\",\"cwd\":\"$D/proj\"}" | CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py"
ls "$P/runs/" | grep -q "2026-01-01T00-00-00Z_csv-export.json" && grep -q '"closed_at"' "$P/runs/"*csv-export.json && echo "PASS run-plan close -> run archived under runs/" || { echo "FAIL run archive"; ls -R "$P"; exit 1; }
rm "$P/routing.json"
OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$D/proj" python3 "$H/ledger.py" --receipts csv-export)
echo "$OUT" | grep -q "receipts: csv-export · dial safe" && echo "$OUT" | grep -q "closed · 3 steps" && echo "PASS --receipts <task> reads the archived run" || { echo "FAIL --receipts <task>:"; echo "$OUT"; exit 1; }
echo "ALL PASS"
