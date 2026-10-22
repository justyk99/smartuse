#!/usr/bin/env bash
# Self-contained test for hooks/ledger.py: synthetic transcript + pending.json -> one ledger line; SubagentStop -> one receipt
# (tokens by model on the line and on the running plan step), none once the run is closed; --receipts summary with the
# agent-output share by model; --json; the state dir keyed by the full path (the 0.3.0 folder-name dir: listed by --receipts, marked
# as shared, never read by the hooks nor written); --state-dir [--create] (always the keyed dir); non-ASCII under cp1252;
# the skills' state writes --put / --unit / --run / --get (keyed dir only, hook- and gate-owned fields kept, typed values).
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj"
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
wp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }   # a path as the interpreter must see it: Git Bash converts POSIX paths in arguments and environment variables for a Windows program, not inside JSON strings (cygpath -m -> C:/Users/...); elsewhere unchanged
key() { py -c "import re,sys,pathlib; print(re.sub(r'[^A-Za-z0-9._-]','-',str(pathlib.Path(sys.argv[1]).resolve())).lstrip('-'))" "$1"; }   # the hooks' state-dir rule: the full resolved path, every character outside [A-Za-z0-9._-] -> "-", no leading "-" (~/.claude/smartuse/projects/<key>/)
T="$D/t.jsonl"; TW=$(wp "$T"); PW=$(wp "$D/proj")   # TW / PW go into the event JSON and CLAUDE_PROJECT_DIR; T and $D/proj stay for the shell itself
K=$(key "$PW"); P="$HOME/.claude/smartuse/projects/$K"; mkdir -p "$P"   # the state dir: keyed by the full path, not the folder name
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:10Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:20Z","message":{"model":"m-a","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":0}}}' \
 '{"type":"assistant","timestamp":"2025-12-31T23:00:00Z","message":{"model":"m-b","usage":{"input_tokens":999,"output_tokens":999}}}' \
 '{"type":"user","timestamp":"2026-01-01T00:00:15Z","message":{}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:30Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:31Z","message":{"id":"dup","model":"m-a","usage":{"input_tokens":5,"output_tokens":5}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:40Z","message":{"id":"grow","model":"m-a","usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":100}}}' \
 '{"type":"assistant","timestamp":"2026-01-01T00:00:41Z","message":{"id":"grow","model":"m-a","usage":{"input_tokens":2,"output_tokens":900,"cache_read_input_tokens":100}}}' > "$T"
mkdir -p "$D/t/subagents"; printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T00:00:50Z","message":{"id":"sub1","model":"m-fork","usage":{"input_tokens":7,"output_tokens":70}}}' '{"type":"assistant","timestamp":"2025-12-31T00:00:00Z","message":{"id":"old","model":"m-fork","usage":{"input_tokens":1,"output_tokens":1}}}' > "$D/t/subagents/agent-x.jsonl"
echo '{"skill":"make-prompt","task":"t","mode":"quick","started_at":"2026-01-01T00:00:00Z","self_check":"13/13"}' > "$P/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
L="$HOME/.claude/smartuse/ledger.jsonl"; [ -f "$L" ] || { echo "FAIL no ledger"; exit 1; }
py - "$L" <<'PY'
import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert r["total_output"]==100+5+900+70, r; assert r["total_input"]==100+100+2000+10+5+2+100+7, r; assert sorted(r["tokens"])==["m-a","m-fork"], r; assert r["assistant_calls"]==5
assert r["project"]=="proj" and r["project_path"].endswith("proj") and len(r["project_path"]) > len("proj"), r
print("PASS stop: main + forked-subagent usage after started_at summed; earlier records ignored; shared id -> max; project + project_path recorded")
PY
[ -f "$P/pending.json" ] && { echo "FAIL pending not removed"; exit 1; } || echo "PASS pending removed"
echo '{"active":true}' > "$P/routing.json"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
grep -q '"agent_id": "a1"' "$P/receipts.jsonl" && echo "PASS subagent receipt written" || { echo "FAIL receipt"; exit 1; }
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
[ "$(grep -c '"agent_id": "a1"' "$P/receipts.jsonl")" = 1 ] && echo "PASS second SubagentStop for the same agent -> no duplicate" || { echo "FAIL duplicate receipt"; exit 1; }
# non-ASCII in the event: Windows Python would decode a piped stdin as cp1252 (Á = C3 81, 0x81 undefined -> error, receipt lost); the hook reads bytes and decodes UTF-8
printf '%s' "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a2\",\"agent_name\":\"Á中文\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | PYTHONIOENCODING=cp1252 CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
grep -q '"agent_name": "Á中文"' "$P/receipts.jsonl" && echo "PASS receipt with Á / 中文 recorded under PYTHONIOENCODING=cp1252 (stdin read as bytes, decoded as UTF-8)" || { echo "FAIL non-ASCII receipt lost"; exit 1; }
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
[ "$(wc -l < "$L" | tr -d ' ')" = 1 ] && echo "PASS no pending -> no new line" || { echo "FAIL wrote without pending"; exit 1; }
echo '{"skill":"living-docs","task":"future","mode":"update","started_at":"2099-01-01T00:00:00Z"}' > "$P/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s3\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
py - "$L" <<'PY'
import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1]); assert r["task"]=="future" and 840 <= r["duration_s"] <= 960 and "future" in (r.get("notes") or ""), r
print("PASS future started_at -> 15-minute window, note added")
PY
# two Stop hooks at once (user-level + plugin copy) must produce ONE line
echo '{"skill":"make-prompt","task":"race","mode":"quick","started_at":"2026-01-01T00:00:00Z"}' > "$P/pending.json"
IN="{\"hook_event_name\":\"Stop\",\"session_id\":\"s2\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW\"}"
( echo "$IN" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" ) & ( echo "$IN" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" ) & wait
[ "$(grep -c '"task": "race"' "$L")" = 1 ] && echo "PASS concurrent hooks -> one line" || { echo "FAIL duplicate line from concurrent hooks"; exit 1; }
# --- receipt per plan step: the agent's tokens land on the unit that is "running" in routing.json
echo '{"active":true,"task":"csv-export","dial":"safe","started_at":"2026-01-01T00:00:00Z","until_done":true,"units":[{"id":1,"title":"decide","tier":"judgment","model":"session","status":"pass"},{"id":2,"title":"build route","tier":"build","model":"opus","why":"has a test","status":"running","check":"npm test"},{"id":3,"title":"tests","tier":"build","model":"opus","status":"pending"}]}' > "$P/routing.json"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"b1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); u=r["units"][1]
assert u["agent_calls"]==5 and u["agent_output"]==2004 and u["agent_input"]==3316 and u["agents"]==["b1"] and u["agent_models"]==["m-a","m-b"], u
assert r["units"][0].get("agent_output") is None and r["units"][2].get("agent_output") is None
line=json.loads(open(P/"receipts.jsonl").read().splitlines()[-1]); assert line["agent_id"]=="b1" and line["unit"]==2, line
# per model in the fixture: m-a = 4 calls (two plain records + "dup" + "grow", a shared id counts once), out 50+50+5+900 = 1005,
# in 207 fresh + 2100 cache-read + 10 cache-create = 2317; m-b = 1 call, in 999 / out 999 (no since on SubagentStop)
BM={"m-a":{"calls":4,"input":2317,"output":1005},"m-b":{"calls":1,"input":999,"output":999}}
assert line["by_model"]==BM, line; assert u["agent_by_model"]==BM, u
print("PASS SubagentStop -> tokens attached to the running step (unit 2), receipt line carries unit; by_model on the line = agent_by_model on the step")
PY
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"b2\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); u=json.load(open(P/"routing.json"))["units"][1]
assert u["agent_calls"]==10 and u["agent_output"]==4008 and u["agents"]==["b1","b2"], u
assert u["agent_by_model"]=={"m-a":{"calls":8,"input":4634,"output":2010},"m-b":{"calls":2,"input":1998,"output":1998}}, u["agent_by_model"]
print("PASS second agent on the same step (verify) accumulates, per model too (m-a 8 calls / 4634 in / 2010 out, m-b 2 / 1998 / 1998)")
PY
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); r["units"][2]["status"]="running"; json.dump(r,open(P/"routing.json","w"))
PY
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"c1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json"))
assert r["units"][1]["agent_calls"]==10 and r["units"][2].get("agent_calls") is None, r
line=json.loads(open(P/"receipts.jsonl").read().splitlines()[-1]); assert line["agent_id"]=="c1" and line["unit"] is None, line
print("PASS two running steps -> receipt stays unattached, nothing guessed")
PY
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); r["units"][1]["status"]="pass"; r["units"][1]["verify"]="no gaps"; r["units"][2]["status"]="blocked"; r["units"][2]["override"]={"from":"mechanical","to":"build","by":"user"}; json.dump(r,open(P/"routing.json","w"))
PY
OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts)
echo "$OUT" | grep -q "| 2 | build route | build | opus |  | pass |  | no gaps | 10 | 6.6k | 4.0k | npm test |" && echo "$OUT" | grep -q "| 3 | tests | build | opus | mechanical→build | blocked |" && echo "$OUT" | grep -q "steps 2 pass · 1 blocked · 0 open" && echo "PASS --receipts: one row per plan step with tier, model, override, outcome, verify, tokens" || { echo "FAIL --receipts output:"; echo "$OUT"; exit 1; }
# share of all agent output tokens (floor): m-a 2010 of 4008 = 50%, m-b 1998 of 4008 = 49%; the larger share first; the old "delegated out" wording is gone
echo "$OUT" | grep -q "agent tokens in 6.6k / out 4.0k · agent out by model: m-a 50% · m-b 49%" && ! echo "$OUT" | grep -q "delegated out" && echo "PASS --receipts summary: agent output share by model, largest first (m-a 50% · m-b 49%)" || { echo "FAIL by-model summary line:"; echo "$OUT"; exit 1; }
# run-plan close -> the Stop hook archives routing.json under runs/ so /smartuse:receipts <task> finds it later
echo '{"skill":"run-plan","task":"csv-export","mode":"safe","started_at":"2026-01-01T00:00:00Z","self_check":"2/3"}' > "$P/pending.json"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s4\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
ls "$P/runs/" | grep -q "2026-01-01T00-00-00Z_csv-export.json" && grep -q '"closed_at"' "$P/runs/"*csv-export.json && echo "PASS run-plan close -> run archived under runs/" || { echo "FAIL run archive"; ls -R "$P"; exit 1; }
[ -z "$(ls "$P" | grep '^receipt\..*\.done$')" ] && echo "PASS archive removes the receipt.<agent>.done markers" || { echo "FAIL markers left after archive: $(ls "$P")"; exit 1; }
# the run is closed (routing.json active: false): a late SubagentStop writes neither a receipt nor a marker
N=$(wc -l < "$P/receipts.jsonl" | tr -d ' ')
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(P/"routing.json")); r["active"]=False; json.dump(r,open(P/"routing.json","w"))
PY
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"late1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py"
[ "$(wc -l < "$P/receipts.jsonl" | tr -d ' ')" = "$N" ] && [ ! -f "$P/receipt.late1.done" ] && echo "PASS inactive routing.json (run closed) -> no receipt, no marker" || { echo "FAIL receipt or marker written after the run closed"; exit 1; }
rm "$P/routing.json"
OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts csv-export)
echo "$OUT" | grep -q "receipts: csv-export · dial safe" && echo "$OUT" | grep -q "closed · 3 steps" && echo "PASS --receipts <task> reads the archived run" || { echo "FAIL --receipts <task>:"; echo "$OUT"; exit 1; }
# --json: one object for a run (steps verbatim + totals by model), a list for "all", no markdown around it
( cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts csv-export --json ) > "$D/one.json"
( cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts all --json ) > "$D/all.json"
py - "$D/one.json" "$D/all.json" <<'PY'
import json,sys; r=json.load(open(sys.argv[1])); l=json.load(open(sys.argv[2]))
assert r["task"]=="csv-export" and r["dial"]=="safe" and r["started_at"]=="2026-01-01T00:00:00Z" and r["closed_at"] and r["active"] is False and r["needs_human"] is None and r["path"].endswith("_csv-export.json") and r["legacy"] is False, r
assert len(r["steps"])==3 and r["steps"][1]["agent_output"]==4008 and r["steps"][1]["verify"]=="no gaps" and r["steps"][2]["override"]["from"]=="mechanical", r["steps"]
# totals over the steps: only unit 2 carries tokens (b1 + b2 = 2 x 3316 in, 2 x 2004 out); by_model = the units' agent_by_model summed
assert r["totals"]["input"]==6632 and r["totals"]["output"]==4008, r["totals"]
assert r["totals"]["by_model"]=={"m-a":{"calls":8,"input":4634,"output":2010},"m-b":{"calls":2,"input":1998,"output":1998}}, r["totals"]["by_model"]
assert isinstance(l,list) and len(l)==1 and l[0]["task"]=="csv-export" and l[0]["totals"]==r["totals"], l
print("PASS --receipts <task> --json: one object with 3 steps verbatim + totals {input, output, by_model}; all --json: a list")
PY
# a run archived by 0.3.0 has agent_models but no agent_by_model -> the summary keeps the old "delegated out" line (never crashes)
py - "$P" <<'PY'
import json,sys,pathlib; P=pathlib.Path(sys.argv[1]); r=json.load(open(next((P/"runs").glob("*_csv-export.json")))); r["task"]="old-run"
for u in r["units"]: u.pop("agent_by_model", None)
json.dump(r, open(P/"runs"/"2025-12-01T00-00-00Z_old-run.json","w"))
PY
OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts old-run)
echo "$OUT" | grep -q "agent tokens in 6.6k / out 4.0k · delegated out 4.0k (100% of agent output) on m-a, m-b" && ! echo "$OUT" | grep -q "agent out by model" && echo "PASS archive without agent_by_model (0.3.0 run) -> old delegated-share line, no crash" || { echo "FAIL old-archive fallback:"; echo "$OUT"; exit 1; }
( cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts old-run --json ) | py -c "import json,sys; r=json.load(sys.stdin); assert r['task']=='old-run' and r['totals']['by_model']=={} and r['totals']['output']==4008, r" && echo "PASS old archive --json: by_model empty, totals still summed" || { echo "FAIL old-archive --json"; exit 1; }
# the state dir is keyed by the full path: a second repo named "proj" elsewhere does not see this one's runs. The 0.3.0 dir keyed by the
# folder name alone (projects/proj) is shared by every repo named proj, so it is display-only: --receipts lists its archived runs (and its
# routing.json once that run is closed but not archived) after the keyed dir's, each marked as shared ("legacy": true in --json); no read
# creates a keyed dir or writes there, and the Stop / SubagentStop hooks never read or write it
LG="$HOME/.claude/smartuse/projects/proj"; mkdir -p "$D/legacy/proj" "$LG/runs"; PW3=$(wp "$D/legacy/proj"); K3=$(key "$PW3")
[ "$K3" != "$K" ] || { echo "FAIL two repos named proj got the same key $K"; exit 1; }
py - "$P" "$LG" <<'PY'
import json,sys,pathlib; P,LG=map(pathlib.Path,sys.argv[1:]); r=json.load(open(next((P/"runs").glob("*_csv-export.json")),encoding="utf-8"))
r.update(task="legacy-run", started_at="2025-11-01T00:00:00Z"); json.dump(r,open(LG/"runs"/"2025-11-01T00-00-00Z_legacy-run.json","w"))
r.update(task="legacy-closed", started_at="2025-11-15T00:00:00Z", active=False); r.pop("closed_at"); json.dump(r,open(LG/"routing.json","w"))   # closed by run-plan, never archived
PY
snap() { py -c 'import hashlib,pathlib,sys; d=pathlib.Path(sys.argv[1]); print(" ".join(sorted(p.relative_to(d).as_posix()+":"+hashlib.sha256(p.read_bytes()).hexdigest()[:16] for p in d.rglob("*") if p.is_file())))' "$1"; }   # every file under $1 with a hash of its bytes
NOTE="(from the 0.3.0 folder-name dir ~/.claude/smartuse/projects/proj/ — shared by every repo of that name)"; T0=$(snap "$LG")
OUT=$(cd "$D/legacy/proj" && CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py" --receipts legacy-run); OUT2=$(cd "$D/legacy/proj" && CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py" --receipts)
echo "$OUT" | grep -q "closed · 3 steps" && echo "$OUT" | grep -q "legacy-run.json" && echo "$OUT" | grep -qF "$NOTE" && echo "$OUT2" | grep -q "receipts: legacy-closed · dial safe" && echo "$OUT2" | grep -qF "$NOTE" && echo "PASS --receipts <task> and --receipts (latest) still show the 0.3.0 folder-name dir's runs (an archived one, the closed routing.json), marked as shared by every repo of that name" || { echo "FAIL 0.3.0 runs not shown or not marked:"; echo "$OUT"; echo "$OUT2"; exit 1; }
( cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts all --json ) > "$D/all2.json"; OUT=$(cd "$D/proj" && CLAUDE_PROJECT_DIR="$PW" py "$H/ledger.py" --receipts all)
py - "$D/all2.json" "$(echo "$OUT" | grep -cF "$NOTE")" <<'PY'
import json,sys; l=json.load(open(sys.argv[1],encoding="utf-8")); got=[(r["task"],r["legacy"]) for r in l]
assert got==[("csv-export",False),("old-run",False),("legacy-closed",True),("legacy-run",True)], got
assert sys.argv[2]=="2", "markdown note lines: " + sys.argv[2]
print("PASS --receipts all: the keyed runs first, then the 0.3.0 dir's (its closed routing.json, its archived run), each marked: a note line in markdown, \"legacy\": true in --json")
PY
OUT=$(cd "$D/legacy/proj" && CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py" --receipts csv-export)
echo "$OUT" | grep -q "receipts: no run-plan run recorded for proj" && echo "PASS a same-named repo elsewhere does not see this repo's keyed runs (csv-export)" || { echo "FAIL same-named repos share keyed runs:"; echo "$OUT"; exit 1; }
[ ! -e "$HOME/.claude/smartuse/projects/$K3" ] && [ "$(snap "$LG")" = "$T0" ] && echo "PASS reading the 0.3.0 dir created no keyed dir and wrote nothing there (same files, same bytes)" || { echo "FAIL a read created $K3 or changed projects/proj: $(snap "$LG")"; exit 1; }
# an active routing.json there is a run the upgrade cut off: not listed; a closed one that was archived too (run-plan's close leaves both) is listed once
py - "$LG" <<'PY'
import json,sys,pathlib; LG=pathlib.Path(sys.argv[1]); r=json.load(open(LG/"routing.json",encoding="utf-8")); r["active"]=True; json.dump(r,open(LG/"routing.json","w"))
PY
( cd "$D/legacy/proj" && CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py" --receipts all --json ) > "$D/legacy-active.json"
cp "$LG/runs/2025-11-01T00-00-00Z_legacy-run.json" "$LG/routing.json"
( cd "$D/legacy/proj" && CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py" --receipts all --json ) > "$D/legacy-dup.json"
py - "$D/legacy-active.json" "$D/legacy-dup.json" <<'PY'
import json,sys; a=json.load(open(sys.argv[1],encoding="utf-8")); b=json.load(open(sys.argv[2],encoding="utf-8"))
assert [(r["task"],r["legacy"]) for r in a]==[("legacy-run",True)], a
assert [(r["task"],r["legacy"]) for r in b]==[("legacy-run",True)] and b[0]["path"].endswith("_legacy-run.json"), b
print("PASS the 0.3.0 dir's active routing.json (a run cut off by the upgrade) is not listed; a closed one that is also archived is listed once")
PY
# Stop / SubagentStop in a repo named proj with no keyed dir: the 0.3.0 dir's pending.json and active routing.json (a running step) are not
# read, so no ledger line, no receipt, no marker, no archive — nothing is written there, and no keyed dir appears
echo '{"skill":"run-plan","task":"legacy-pending","mode":"safe","started_at":"2026-01-01T00:00:00Z"}' > "$LG/pending.json"
echo '{"active":true,"task":"legacy-pending","units":[{"id":1,"title":"old step","status":"running"}]}' > "$LG/routing.json"
T1=$(snap "$LG"); N=$(wc -l < "$L" | tr -d ' ')
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s5\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW3\"}" | CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py"
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s5\",\"agent_id\":\"leg1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW3\"}" | CLAUDE_PROJECT_DIR="$PW3" py "$H/ledger.py"
[ "$(wc -l < "$L" | tr -d ' ')" = "$N" ] && [ "$(snap "$LG")" = "$T1" ] && [ ! -e "$HOME/.claude/smartuse/projects/$K3" ] && echo "PASS Stop / SubagentStop ignore the 0.3.0 dir: its pending.json and active routing.json are not consumed (no ledger line, receipt, marker or archive; nothing written; no keyed dir)" || { echo "FAIL a hook used the 0.3.0 dir: ledger $(wc -l < "$L" | tr -d ' ') lines (was $N) · $(snap "$LG")"; exit 1; }
# --state-dir prints the dir the hooks will use for CLAUDE_PROJECT_DIR (else the cwd) by the same rule, as a path bash can use,
# and creates nothing; --create makes it (the skills' live context runs that, so a skill writes where the hooks read); a 0.3.0
# folder-name dir changes nothing: it is always the keyed dir
same() { py -c 'import sys,pathlib; sys.exit(0 if pathlib.Path(sys.argv[1]).resolve()==pathlib.Path(sys.argv[2]).resolve() else 1)' "$1" "$2"; }   # path equality whatever the slashes (Windows python prints C:/..., cygpath -m too)
mkdir -p "$D/sd/fresh"; PW4=$(wp "$D/sd/fresh"); K4=$(key "$PW4"); E4="$HOME/.claude/smartuse/projects/$K4"   # "fresh": no projects/fresh dir exists (projects/proj does, from the 0.3.0 cases above)
OUT=$(cd "$D/sd/fresh" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --state-dir)
same "$OUT" "$(wp "$E4")" && [ ! -e "$E4" ] && echo "PASS --state-dir: prints the keyed dir for the cwd (not projects/fresh), creates nothing" || { echo "FAIL --state-dir: printed '$OUT', expected '$E4' (exists: $([ -e "$E4" ] && echo yes || echo no))"; exit 1; }
OUT=$(cd "$D" && CLAUDE_PROJECT_DIR="$PW4" py "$H/ledger.py" --state-dir)
same "$OUT" "$(wp "$E4")" && [ ! -e "$E4" ] && echo "PASS --state-dir: CLAUDE_PROJECT_DIR wins over the cwd, still nothing created" || { echo "FAIL --state-dir with CLAUDE_PROJECT_DIR: printed '$OUT', expected '$E4'"; exit 1; }
OUT=$(cd "$D/sd/fresh" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --state-dir --create)
same "$OUT" "$(wp "$E4")" && [ -d "$E4" ] && echo "PASS --state-dir --create: creates the keyed dir and prints it" || { echo "FAIL --state-dir --create: printed '$OUT', dir exists: $([ -d "$E4" ] && echo yes || echo no)"; exit 1; }
mkdir -p "$D/sd2/old" "$HOME/.claude/smartuse/projects/old"; PW5=$(wp "$D/sd2/old"); K5=$(key "$PW5"); E5="$HOME/.claude/smartuse/projects/$K5"
OUT=$(cd "$D/sd2/old" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --state-dir)
same "$OUT" "$(wp "$E5")" && [ ! -e "$E5" ] && echo "PASS --state-dir: with only the 0.3.0 folder-name dir present (projects/old) it still prints the keyed dir, creates nothing" || { echo "FAIL --state-dir with projects/old present: printed '$OUT', expected '$E5' (exists: $([ -e "$E5" ] && echo yes || echo no))"; exit 1; }
OUT=$(cd "$D/sd2/old" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --state-dir --create)
same "$OUT" "$(wp "$E5")" && [ -d "$E5" ] && [ -z "$(ls -A "$HOME/.claude/smartuse/projects/old")" ] && echo "PASS --state-dir --create with projects/old present: creates and prints the keyed dir, projects/old untouched" || { echo "FAIL --state-dir --create with projects/old present: printed '$OUT', keyed dir: $([ -d "$E5" ] && echo yes || echo no), projects/old: $(ls -A "$HOME/.claude/smartuse/projects/old")"; exit 1; }
# --- the skills' state writes: --put / --unit / --run / --get. Claude Code treats ~/.claude/ as a sensitive path (Write / Edit there
# prompt in default and acceptEdits mode and are denied headless), so the skills write pending.json / routing.json only through this
# script, which their Bash(bash *) already runs. Run from the repo with CLAUDE_PROJECT_DIR unset, the way the Bash tool runs it; every
# write must land in that repo's keyed dir and nowhere else (others() = every file under HOME outside the keyed dir, with its hash).
mkdir -p "$D/st/proj"; PW6=$(wp "$D/st/proj"); K6=$(key "$PW6"); E6="$HOME/.claude/smartuse/projects/$K6"
st() { ( cd "$D/st/proj" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" "$@" ); }
others() { snap "$HOME" | tr ' ' '\n' | grep -vF ".claude/smartuse/projects/$K6/" || true; }
O0=$(others); [ ! -e "$E6" ] || { echo "FAIL $E6 exists before the first --put"; exit 1; }
# the skills' form: the JSON as ONE single-quoted argument (Claude Code's Bash check refuses a JSON heredoc in default mode)
PJ='{"skill":"make-prompt","task":"Á中文","mode":"quick","started_at":"2026-01-01T00:00:00Z","notes":"sudo and git push --force are only text here"}'
RC=0; OUT=$(st --put pending.json "$PJ" < /dev/null 2>&1) || RC=$?
[ "$RC" = 0 ] && [ "${OUT%% → *}" = "put pending.json" ] && same "${OUT#* → }" "$(wp "$E6/pending.json")" && py - "$E6/pending.json" "$PJ" <<'PY' && echo "PASS --put pending.json '<json>': the one JSON argument (Á中文 kept) -> the keyed dir, created; prints 'put pending.json → <path>'" || { echo "FAIL --put pending.json '<json>': exit $RC, printed '$OUT'"; exit 1; }
import json,sys; p=json.load(open(sys.argv[1],encoding="utf-8")); assert p==json.loads(sys.argv[2]) and p["task"]=="Á中文", p
PY
rm "$E6/pending.json"
RC=0; OUT=$(printf '%s\n' "$PJ" | PYTHONIOENCODING=cp1252 st --put pending.json 2>&1) || RC=$?
[ "$RC" = 0 ] && [ "${OUT%% → *}" = "put pending.json" ] && py - "$E6/pending.json" "$PJ" <<'PY' && echo "PASS --put pending.json < stdin (a pipe or heredoc): bytes read as UTF-8 (Á中文 under PYTHONIOENCODING=cp1252), same file" || { echo "FAIL --put pending.json from stdin: exit $RC, printed '$OUT'"; exit 1; }
import json,sys; p=json.load(open(sys.argv[1],encoding="utf-8")); assert p==json.loads(sys.argv[2]), p
PY
S0=$(snap "$E6"); rc=""
for bad in '{"skill": "make-prompt", "task":' '["not", "an", "object"]' '{"started_at": NaN}' ''; do RC=0; OUT=$(printf '%s' "$bad" | st --put pending.json 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"; done
RC=0; OUT=$(st --put pending.json '{"a": 1}' '{"b": 2}' < /dev/null 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
RC=0; OUT=$(st --put routing.json '{"units": [{"id": 1}, {"id": 1}]}' < /dev/null 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
RC=0; OUT=$(printf '%s' '{"units": {"id": 1}}' | st --put routing.json 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
RC=0; OUT=$(st --put status.json '{"a": 1}' < /dev/null 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
[ "$rc" = " 1:put refused 1:put refused 1:put refused 1:put refused 1:put refused 1:put refused 1:put refused 1:put refused" ] && [ "$(snap "$E6")" = "$S0" ] && echo "PASS --put refuses bad JSON, a non-object, NaN, empty input, two JSON arguments, units that are not a list of objects or repeat an id, and a file other than pending.json / routing.json: 'put refused: …', exit 1, nothing written" || { echo "FAIL --put refusals: '$rc' · $(snap "$E6")"; exit 1; }
cat > "$D/plan.json" <<'JSON'
{"active": true, "task": "st-run", "dial": "safe", "started_at": "2026-02-01T00:00:00Z", "until_done": true, "units": [
 {"id": 1, "title": "decide", "tier": "judgment", "model": "session", "status": "pass"},
 {"id": 2, "title": "build route", "tier": "build", "model": "opus", "why": "has a test", "status": "pending", "check": null},
 {"id": 3, "title": "force-push cleanup with sudo", "tier": "mechanical", "model": "haiku", "status": "pending"}]}
JSON
RC=0; OUT=$(st --put routing.json "$(cat "$D/plan.json")" < /dev/null 2>&1) || RC=$?
[ "$RC" = 0 ] && [ "${OUT%% → *}" = "put routing.json" ] && same "${OUT#* → }" "$(wp "$E6/routing.json")" && py - "$E6/routing.json" "$D/plan.json" <<'PY' && echo "PASS --put routing.json '<json>': the plan (a multi-line argument) lands in the keyed dir as given" || { echo "FAIL --put routing.json: exit $RC, printed '$OUT'"; exit 1; }
import json,sys; assert json.load(open(sys.argv[1],encoding="utf-8"))==json.load(open(sys.argv[2],encoding="utf-8"))
PY
# step 2 runs: the real SubagentStop hook attaches the agent's tokens to it, the real until-done gate blocks once (blocks, last_block);
# then the plan is put again for the SAME run (same task + started_at) — those fields are kept unless the new JSON sets them
OUT=$(st --unit 2 status=running)
echo "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s6\",\"agent_id\":\"st1\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW6\"}" | CLAUDE_PROJECT_DIR="$PW6" py "$H/ledger.py"
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s6\",\"cwd\":\"$PW6\"}" | CLAUDE_PROJECT_DIR="$PW6" py "$H/until-done.py" > /dev/null
py - "$D/plan.json" "$D/plan2.json" <<'PY'
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8")); r["units"][1].update(status="pass", agent_calls=7); r["units"][2]["status"]="running"; json.dump(r,open(sys.argv[2],"w",encoding="utf-8"))
PY
st --put routing.json "$(cat "$D/plan2.json")" < /dev/null > /dev/null
py - "$E6/routing.json" <<'PY' || { echo "FAIL hook-owned fields lost on a re-put of the same run"; exit 1; }
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8")); u=r["units"][1]
assert u["status"]=="pass" and u["agent_calls"]==7, u   # the new JSON set agent_calls: it wins
assert u["agent_input"]==3316 and u["agent_output"]==2004 and u["agents"]==["st1"] and u["agent_models"]==["m-a","m-b"], u
assert u["agent_by_model"]=={"m-a":{"calls":4,"input":2317,"output":1005},"m-b":{"calls":1,"input":999,"output":999}}, u
assert r["blocks"]==1 and r["last_block"] and r["units"][2]["status"]=="running" and "agent_output" not in r["units"][2], r
print("PASS --put routing.json again for the same run keeps the SubagentStop tokens on step 2 (agent_input / output / models / by_model / agents) and the gate's blocks + last_block; a field the new JSON sets (agent_calls 7) wins")
PY
RC=0; OUT=$(st --unit 2 status=pass verify='no gaps' escalated=true budget_turns=15 'files=["src/a.js","src/b.js"]' 'override={"from":"mechanical","to":"build","by":"user"}' 'check=12 passing' blocked_by=null 2>&1) || RC=$?
[ "$RC" = 0 ] && echo "$OUT" | grep -qF 'unit 2/3 · build·opus · pass · verify no gaps · escalated · override mechanical→build · "build route"' && py - "$E6/routing.json" <<'PY' && echo "PASS --unit 2 key=value …: merged into step 2 only, values typed as JSON when they parse (true, 15, a list, an object, null) else text; agent_* untouched; prints the step's line" || { echo "FAIL --unit merge: exit $RC, printed '$OUT'"; exit 1; }
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8")); u=r["units"][1]
assert u["status"]=="pass" and u["verify"]=="no gaps" and u["escalated"] is True and u["budget_turns"]==15 and isinstance(u["budget_turns"],int), u
assert u["files"]==["src/a.js","src/b.js"] and u["override"]=={"from":"mechanical","to":"build","by":"user"} and u["check"]=="12 passing" and u["blocked_by"] is None, u
assert u["agent_output"]==2004 and u["agent_calls"]==7 and r["units"][0]=={"id":1,"title":"decide","tier":"judgment","model":"session","status":"pass"} and r["units"][2]["status"]=="running", r
PY
S1=$(snap "$E6"); rc=""
RC=0; OUT=$(st --unit 9 status=pass 2>&1) || RC=$?; rc="$rc $RC:$OUT"
RC=0; OUT=$(st --unit 2 agent_output=0 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
RC=0; OUT=$(st --unit 2 status 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"
[ "$rc" = " 1:unit refused: no unit 9 in routing.json (units: 1, 2, 3) 1:unit refused 1:unit refused" ] && [ "$(snap "$E6")" = "$S1" ] && echo "PASS --unit refuses an unknown id (names the known ones), a hook-owned field (agent_output) and a word without '=': exit 1, routing.json unchanged" || { echo "FAIL --unit refusals: '$rc'"; exit 1; }
RC=0; OUT=$(st --run needs_human='which rounding rule?' active=false 2>&1) || RC=$?
[ "$RC" = 0 ] && echo "$OUT" | grep -qF "run st-run · dial safe · closed · until-done · steps 2 pass · 0 blocked · 1 open · needs_human: which rounding rule?" && py - "$E6/routing.json" <<'PY' && echo "PASS --run key=value …: top-level fields (needs_human as text, active=false as a boolean), the steps and the gate's blocks untouched; prints the run's line" || { echo "FAIL --run: exit $RC, printed '$OUT'"; exit 1; }
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8"))
assert r["needs_human"]=="which rounding rule?" and r["active"] is False and r["blocks"]==1 and [u["status"] for u in r["units"]]==["pass","pass","running"], r
PY
S2=$(snap "$E6"); rc=""
for kv in blocks=0 last_block=null check_error=null 'units=[]' oops; do RC=0; OUT=$(st --run "$kv" 2>&1) || RC=$?; rc="$rc $RC:${OUT%%:*}"; done
RC=0; OUT=$(cd "$D/sd/fresh" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --run active=false 2>&1) || RC=$?; rc="$rc $RC:${OUT%% in *}"
[ "$rc" = " 1:run refused 1:run refused 1:run refused 1:run refused 1:run refused 1:run refused: no routing.json" ] && [ "$(snap "$E6")" = "$S2" ] && [ ! -e "$E4/routing.json" ] && echo "PASS --run refuses the gate's blocks / last_block / check_error, units (that is --put or --unit) and a word without '='; with no routing.json it refuses and creates none" || { echo "FAIL --run refusals: '$rc'"; exit 1; }
st --get routing.json > "$D/got.json"; ( cd "$D" && CLAUDE_PROJECT_DIR="$PW6" py "$H/ledger.py" --get pending.json ) > "$D/gotp.json"
mkdir -p "$D/st/none"; K7=$(key "$(wp "$D/st/none")"); OUT=$(cd "$D/st/none" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" --get routing.json)
[ "$OUT" = "{}" ] && [ ! -e "$HOME/.claude/smartuse/projects/$K7" ] && py - "$D/got.json" "$E6/routing.json" "$D/gotp.json" <<'PY' && echo "PASS --get routing.json / pending.json prints the stored file (CLAUDE_PROJECT_DIR wins over the cwd); {} for a repo with no state, creating nothing" || { echo "FAIL --get: printed '$OUT' for a repo without state"; exit 1; }
import json,sys; assert json.load(open(sys.argv[1],encoding="utf-8"))==json.load(open(sys.argv[2],encoding="utf-8")); assert json.load(open(sys.argv[3],encoding="utf-8"))["task"]=="Á中文"
PY
[ "$(others)" = "$O0" ] && [ -z "$(ls -A "$D/st/proj")" ] && echo "PASS every --put / --unit / --run / --get above wrote in the keyed dir only: no other file under HOME changed, nothing in the repo" || { echo "FAIL a state write landed outside $E6"; others; ls -A "$D/st/proj"; exit 1; }
# the hooks read what --put wrote: run-plan's close (--run active=false above, then --put pending.json) -> the Stop hook writes the ledger
# line and archives routing.json with its tokens; the next run's plan (another started_at) then starts clean over the closed run's file
st --put pending.json '{"skill":"run-plan","task":"st-run","mode":"safe","started_at":"2026-02-01T00:00:00Z","self_check":"2/3"}' < /dev/null > /dev/null
echo "{\"hook_event_name\":\"Stop\",\"session_id\":\"s6\",\"transcript_path\":\"$TW\",\"cwd\":\"$PW6\"}" | CLAUDE_PROJECT_DIR="$PW6" py "$H/ledger.py"
py - "$L" "$E6" <<'PY' || { echo "FAIL the Stop hook did not consume the --put pending.json / archive the run"; ls -R "$E6"; exit 1; }
import json,sys,pathlib; r=json.loads(open(sys.argv[1],encoding="utf-8").read().splitlines()[-1]); E=pathlib.Path(sys.argv[2])
assert r["skill"]=="run-plan" and r["task"]=="st-run" and r["session_id"]=="s6" and r["self_check"]=="2/3", r
a=json.load(open(E/"runs"/"2026-02-01T00-00-00Z_st-run.json",encoding="utf-8")); assert not (E/"pending.json").exists()
assert a["active"] is False and a["closed_at"] and a["needs_human"]=="which rounding rule?" and a["units"][1]["agent_output"]==2004 and a["units"][1]["verify"]=="no gaps", a
print("PASS the Stop hook reads what --put wrote: the run-plan pending.json becomes the ledger line, routing.json is archived under runs/ with step 2's tokens")
PY
py - "$D/plan.json" "$D/plan3.json" <<'PY'
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8")); r["started_at"]="2026-03-01T00:00:00Z"; json.dump(r,open(sys.argv[2],"w",encoding="utf-8"))
PY
st --put routing.json < "$D/plan3.json" > /dev/null   # stdin works for a plan too
py - "$E6/routing.json" <<'PY' || { echo "FAIL a new run inherited the closed run's tokens or block count"; exit 1; }
import json,sys; r=json.load(open(sys.argv[1],encoding="utf-8"))
assert r["started_at"]=="2026-03-01T00:00:00Z" and r["active"] is True and not any(k in r for k in ("blocks","last_block","check_error","needs_human")), r
assert not any(k.startswith("agent") for u in r["units"] for k in u), r["units"]
print("PASS --put routing.json for a new run (another started_at) over the closed run's file starts clean: no blocks, no needs_human, no agent tokens carried over")
PY
[ "$(others | grep -vF '.claude/smartuse/ledger.jsonl:')" = "$(echo "$O0" | grep -vF '.claude/smartuse/ledger.jsonl:')" ] && [ -z "$(ls -A "$D/st/proj")" ] && [ -z "$(ls -A "$E6" | grep '\.tmp$')" ] && echo "PASS after the whole run only the keyed dir (and the Stop hook's ledger line) changed; no .tmp file left behind" || { echo "FAIL files changed outside $E6 or a .tmp was left: $(ls -A "$E6")"; exit 1; }
# the hook reads the MSYS path form too: on Windows "/c/Users/x/t.jsonl" inside the event JSON (Git Bash converts arguments and
# environment variables, not JSON strings) is opened as "C:/Users/x/t.jsonl"; "/tmp/..." and "C:/..." are left alone, elsewhere nothing changes
py - "$H/ledger.py" <<'PY'
import os,sys; ns={}; exec(compile(open(sys.argv[1],encoding="utf-8").read().replace("\nmain()\n","\n"),"ledger","exec"),ns); np=ns["native_path"]
assert os.name=="nt" or np("/c/Users/x/t.jsonl")=="/c/Users/x/t.jsonl", "must be a no-op off Windows"
os.name="nt"; assert np("/c/Users/x/t.jsonl")=="C:/Users/x/t.jsonl" and np("/tmp/tmp.X/t.jsonl")=="/tmp/tmp.X/t.jsonl" and np("C:/Users/x")=="C:/Users/x" and np("")=="" and np(None) is None
print("PASS native_path: /c/Users/x -> C:/Users/x on Windows only; /tmp/... and C:/... untouched")
PY
echo "ALL PASS"
