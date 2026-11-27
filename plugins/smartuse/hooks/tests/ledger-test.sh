#!/usr/bin/env bash
# Self-contained test for hooks/ledger.py: synthetic transcript + pending.json -> one ledger line; SubagentStop -> one receipt
# (tokens by model on the line and on the running plan step), none once the run is closed; --receipts summary with the
# agent-output share by model; --json; the state dir keyed by the full path (the 0.3.0 folder-name dir: listed by --receipts, marked
# as shared, never read by the hooks nor written); --state-dir [--create] (always the keyed dir); non-ASCII under cp1252;
# the skills' state writes --put / --unit / --run / --get (keyed dir only, hook- and gate-owned fields kept, typed values);
# --view (0.7.7): --report's table, then the --receipts block of each run-plan run shown, read only (the last block of this file).
set -e; D=$(mktemp -d); H="$(cd "$(dirname "$0")/.." && pwd)"; export HOME="$D/home"; mkdir -p "$HOME" "$D/proj"
py() { bash "$H/py.sh" "$@"; }   # the plugin's launcher: python3, else python, else py -3 (on stock Windows python3 is only the Store stub)
REAL=$(py -c "import sys; sys.stdout.write(sys.executable)")   # the interpreter the launcher found: the two cp1252 cases start it directly, because the launcher's -I ignores PYTHONIOENCODING (0.7.5)
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
printf '%s' "{\"hook_event_name\":\"SubagentStop\",\"session_id\":\"s\",\"agent_id\":\"a2\",\"agent_name\":\"Á中文\",\"agent_transcript_path\":\"$TW\",\"cwd\":\"$PW\"}" | PYTHONUTF8=1 PYTHONIOENCODING=cp1252 CLAUDE_PROJECT_DIR="$PW" "$REAL" "$H/ledger.py"
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
# script, which each skill's launcher rule (py.sh, this script, one option) runs. Run from the repo with CLAUDE_PROJECT_DIR unset, the way the Bash tool runs it; every
# write must land in that repo's keyed dir and nowhere else (others() = every file under HOME outside the keyed dir, with its hash).
mkdir -p "$D/st/proj"; PW6=$(wp "$D/st/proj"); K6=$(key "$PW6"); E6="$HOME/.claude/smartuse/projects/$K6"
st() { ( cd "$D/st/proj" && env -u CLAUDE_PROJECT_DIR bash "$H/py.sh" "$H/ledger.py" "$@" ); }
st1252() { ( cd "$D/st/proj" && env -u CLAUDE_PROJECT_DIR PYTHONUTF8=1 PYTHONIOENCODING=cp1252 "$REAL" "$H/ledger.py" "$@" ); }   # st, started directly in a cp1252 console (0.7.5: the launcher ignores PYTHONIOENCODING)
others() { snap "$HOME" | tr ' ' '\n' | grep -vF ".claude/smartuse/projects/$K6/" || true; }
O0=$(others); [ ! -e "$E6" ] || { echo "FAIL $E6 exists before the first --put"; exit 1; }
# the skills' form: the JSON as ONE single-quoted argument (Claude Code's Bash check refuses a JSON heredoc in default mode)
PJ='{"skill":"make-prompt","task":"Á中文","mode":"quick","started_at":"2026-01-01T00:00:00Z","notes":"sudo and git push --force are only text here"}'
RC=0; OUT=$(st --put pending.json "$PJ" < /dev/null 2>&1) || RC=$?
[ "$RC" = 0 ] && [ "${OUT%% → *}" = "put pending.json" ] && same "${OUT#* → }" "$(wp "$E6/pending.json")" && py - "$E6/pending.json" "$PJ" <<'PY' && echo "PASS --put pending.json '<json>': the one JSON argument (Á中文 kept) -> the keyed dir, created; prints 'put pending.json → <path>'" || { echo "FAIL --put pending.json '<json>': exit $RC, printed '$OUT'"; exit 1; }
import json,sys; p=json.load(open(sys.argv[1],encoding="utf-8")); assert p==json.loads(sys.argv[2]) and p["task"]=="Á中文", p
PY
rm "$E6/pending.json"
RC=0; OUT=$(printf '%s\n' "$PJ" | st1252 --put pending.json 2>&1) || RC=$?
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
# --- 0.7.3 F1: two Stop hooks at once must leave one line. A hook that renamed pending.json to pending.<pid>.claimed reads it; while the other
# hook still holds a handle for its own rename, that read raises PermissionError (Windows sharing violation). It is retried (5 x 20 ms) and the
# claimed file is deleted only when its content is bad; one still unreadable after 5 tries is left, bytes unchanged (D-YK24).
# L2..L7 load the hook in process (as above) and stand in for Path.read_text of the claimed file (a pass-through wrapper that counts the reads);
# L1 also holds a real handle (hold.py, Windows only) and asserts 2 or more reads, so it fails when the read lands after the release.
# L6 (0.7.3 fix round A): content too deeply nested for the parser raises RecursionError, not ValueError: bad content, deleted as bad JSON is.
# L7: a leftover pending.<this pid>.claimed (a reused PID after the 5-try path) must not block the next claim: os.replace, not os.rename.
cat > "$D/l.py" <<'PY'
import os, sys, json, pathlib, tempfile, time, subprocess
src, case = sys.argv[1], sys.argv[2]
ns = {}; exec(compile(open(src, encoding="utf-8").read().replace("\nmain()\n", "\n"), "ledger", "exec"), ns)
tmp = pathlib.Path(tempfile.mkdtemp(dir=os.environ["HOME"])); proj = tmp / "proj"; proj.mkdir()
ns["PROJECTS"] = tmp / "projects"; ns["LEDGER"] = tmp / "ledger.jsonl"   # the hook's own globals, pointed at the temp HOME
os.environ["CLAUDE_PROJECT_DIR"] = str(proj)
sdir = ns["state_dir"](proj, create=True); pending = sdir / "pending.json"; claimed = sdir / f"pending.{os.getpid()}.claimed"
raw = b'{"skill": ' if case == "L4" else b"[" * 100000 if case == "L6" else ('{"skill":"make-prompt","task":"%s","mode":"quick","started_at":"2026-01-01T00:00:00Z"}' % case).encode()
if case == "L7":
    claimed.write_bytes(b"stale bytes left by an earlier hook that had this PID")   # a 5-try leftover under this very PID (Windows PID reuse)
pending.write_bytes(raw)
holder = None
if case == "L1":   # a real handle on pending.json (Windows only), as hold.py opens it; hold.py ends about 30 ms after a claimed name appears
    ready = tmp / "l1.ready"
    holder = subprocess.Popen([sys.executable, sys.argv[3], str(pending), str(ready)])
    for _ in range(200):
        if ready.exists():
            break
        time.sleep(0.05)
    assert ready.exists(), "L1: the helper never got its handle"
reads = []; orig = pathlib.Path.read_text
def fake(self, *a, **k):
    if self.name.endswith(".claimed"):
        reads.append(1)
        if (case == "L2" and len(reads) <= 2) or case == "L3":
            raise PermissionError(13, "sharing violation")
        if case == "L5":
            raise FileNotFoundError(2, "the other hook's rename took the file")
    return orig(self, *a, **k)
pathlib.Path.read_text = fake
err = None; t0 = time.time()
try:
    ns["on_stop"]({"session_id": "s-" + case, "transcript_path": "", "cwd": str(proj)})
except Exception as e:
    err = e
dt = time.time() - t0; pathlib.Path.read_text = orig
lines = [json.loads(l) for l in ns["LEDGER"].read_text(encoding="utf-8").splitlines()] if ns["LEDGER"].exists() else []
n = len([r for r in lines if r.get("task") == case]); left = sorted(os.listdir(sdir))
hrc = holder.wait(timeout=30) if holder else 0
assert err is None, ("the hook raised", err)
if case == "L1":
    assert hrc == 0, ("the helper did not see a claimed name", hrc)
    assert len(reads) >= 2 and n == 1 and left == [], (n, len(reads), left)
    print("PASS L1: pending.json held open with delete access (a rename in progress), released about 30 ms after the claim -> %d reads (the first ones hit the held handle), one line, no pending.json, no claimed file left" % len(reads))
elif case == "L6":
    assert n == 0 and len(reads) == 1 and left == [], (n, len(reads), left)
    print("PASS L6: nesting too deep for the parser (RecursionError, '[' * 100000) -> no line, one read, claimed file deleted")
elif case == "L7":
    assert n == 1 and left == [], (n, len(reads), left)
    print("PASS L7: a stale pending.<this pid>.claimed already there -> the claim still works: one line for the fresh task, no pending or claimed file left")
elif case == "L2":
    assert n == 1 and len(reads) == 3 and left == [], (n, len(reads), left)
    print("PASS L2: claimed file unreadable twice (PermissionError) then readable -> one line after 3 reads, no claimed file left")
elif case == "L3":
    assert n == 0 and len(reads) == 5 and left == [claimed.name] and claimed.read_bytes() == raw and dt < 0.5, (n, len(reads), left, dt)
    print("PASS L3: claimed file unreadable on all 5 tries -> no line, exactly 5 reads, file left with its bytes, wait %.0f ms" % (dt * 1000))
elif case == "L4":
    assert n == 0 and len(reads) == 1 and left == [], (n, len(reads), left)
    print("PASS L4: broken JSON in the claimed file -> no line, one read, claimed file deleted")
elif case == "L5":
    assert n == 0 and len(reads) == 1 and left == [claimed.name] and claimed.read_bytes() == raw, (n, len(reads), left)
    print("PASS L5: claimed file gone (FileNotFoundError: the other hook's rename took it) -> no line, one read, nothing created or deleted")
PY
cat > "$D/hold.py" <<'PY'
import ctypes, ctypes.wintypes as w, sys, time, pathlib
path, ready = sys.argv[1], pathlib.Path(sys.argv[2]); d = pathlib.Path(path).parent
k = ctypes.WinDLL("kernel32", use_last_error=True)
k.CreateFileW.restype = w.HANDLE; k.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, w.LPVOID, w.DWORD, w.DWORD, w.HANDLE]
k.CloseHandle.argtypes = [w.HANDLE]
h = k.CreateFileW(path, 0x80000000 | 0x00010000, 7, None, 3, 0x80, None)   # read + delete access, share read/write/delete, open existing: what a rename in progress holds
if h in (None, ctypes.c_void_p(-1).value):
    sys.exit("cannot open " + path)
ready.write_text("held")
end = time.time() + 20
while time.time() < end and (d / "pending.json").exists() and not list(d.glob("pending.*.claimed")):   # a claimed name appears (pending.json is gone too: the hook may delete a claimed file between two polls)
    time.sleep(0.001)
time.sleep(0.03)   # let go about 30 ms after a claimed name appears: the hook's first read comes within microseconds, so a busy machine still sees 2 or more reads (the retry waits 20 ms)
k.CloseHandle(h)
sys.exit(0 if time.time() < end else 2)
PY
if [ "$(py -c 'import os; print(os.name)')" = nt ]; then
  py "$D/l.py" "$H/ledger.py" L1 "$(wp "$D/hold.py")" || { echo "FAIL L1 (see the assertion above)"; exit 1; }   # in process, with the real handle from hold.py and a counting wrapper on Path.read_text
else
  echo "SKIP L1 held handle: Windows only"
fi
for c in L2 L3 L4 L5 L6 L7; do py "$D/l.py" "$H/ledger.py" $c || { echo "FAIL $c (see the assertion above)"; exit 1; }; done
# --- ledger.py --view (0.7.7 V1): look B = --report's table, then the --receipts block of each run-plan run shown, each read from that run's
# own archive (runs/<started_at>_<task>.json in the state dir its project_path gives), or `steps: not kept (<archive>)`; a last block `running now`
# while this project's routing.json is active. Read only. The ledger is anyone's data: a line it cannot print is skipped and counted, a printed field is
# cleaned. Own temp HOMEs (one per case) and a small invented fixture (vbuild.py: three projects, tokens invented, the steps of the repo's public
# example run); the paths in the output are made stable by norm.py (the HOME shown as ~, the sample-repo state key as <key>).
EXJ="$H/../../../bench/results-example/2026-10-21-csv-export/routing-archived.json"; [ -f "$EXJ" ] || { echo "FAIL the repo's example run is not at $EXJ"; exit 1; }; EXJ=$(wp "$EXJ")
mkdir -p "$D/vp/sample-repo" "$D/vp/shop-api" "$D/vp/docs-site"; VKEY=$(key "$(wp "$D/vp/sample-repo")")
cat > "$D/norm.py" <<'PY'
import sys
t = sys.stdin.read().replace("\r", "").replace("\\", "/")
for a, b in ((sys.argv[1], "~"), (sys.argv[2], "<key>")):
    t = t.replace(a, b)
sys.stdout.buffer.write(t.encode("utf-8"))   # bytes: no CRLF on Windows
PY
cat > "$D/vbuild.py" <<'PY'
"""Fixture builder for the --view cases of ledger-test.sh. usage: vbuild.py <mode> <home> <example routing-archived.json> <dir sample-repo> <dir shop-api> <dir docs-site>
Writes only under <home>/.claude/smartuse/. The data is invented except the steps of the repo's public example run; every token cell is invented."""
import sys, json, re, pathlib, datetime
mode, home, ex = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
proj = dict(zip(("sample-repo", "shop-api", "docs-site"), map(pathlib.Path, sys.argv[4:7])))
SM = home / ".claude" / "smartuse"


def key(p):
    return re.sub(r"[^A-Za-z0-9._-]", "-", str(pathlib.Path(p).resolve())).lstrip("-")


def safe(s):
    return "".join(c if c.isalnum() or c in "-_." else "-" for c in str(s))[:80]


def line(project, task, skill, mode, start, dur_s, calls, t_in, t_out, check, path=None):
    t0 = datetime.datetime.strptime(start, "%Y-%m-%dT%H:%M:%SZ")
    end = (t0 + datetime.timedelta(seconds=dur_s)).strftime("%Y-%m-%dT%H:%M:%SZ")
    cr, cc = int(t_in * 0.82), int(t_in * 0.16)
    tokens = {"claude-fable-5-1": {"input": t_in - cr - cc, "output": t_out, "cache_read": cr, "cache_create": cc, "calls": calls}}
    return {"ts": end, "project": project, "project_path": str(proj[project].resolve()) if path is None else path, "session_id": "s-" + task,
            "skill": skill, "task": task, "mode": mode, "started_at": start, "duration_s": dur_s, "assistant_calls": calls, "tokens": tokens,
            "total_input": t_in, "total_output": t_out, "self_check": check, "corrections": None, "notes": "test fixture"}


def archive(project, task, start, edit=None):
    run = json.loads(ex.read_text(encoding="utf-8"))
    run["task"], run["started_at"] = task, start
    if edit:
        edit(run)
    d = SM / "projects" / key(proj[project]) / "runs"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{safe(start)}_{safe(task)}.json").write_text(json.dumps(run, indent=2), encoding="utf-8")


def write(rows):
    SM.mkdir(parents=True, exist_ok=True)
    (SM / "ledger.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")


EX = [line("sample-repo", "csv-export-orders", "make-prompt", "quick", "2026-10-21T15:13:36Z", 144, 6, 186420, 9310, "14/14"),
      line("sample-repo", "csv-export-orders", "run-plan", "safe", "2026-10-21T15:16:00Z", 384, 22, 1203800, 21650, "5/6")]
if mode == "example":      # the repo's example run: its six steps archived, and two ledger lines rebuilt from its README (2.4 and 6.4 minutes)
    archive("sample-repo", "csv-export-orders", "2026-10-21T15:16:00Z")
    write(EX)
elif mode == "nosteps":    # the run-plan run's own archive is gone; another run of the same task has one (another start time)
    archive("sample-repo", "csv-export-orders", "2026-10-22T09:00:00Z", edit=lambda r: r["units"][0].__setitem__("title", "OTHER-RUN-STEP"))
    write(EX + [line("sample-repo", "csv-export-orders", "living-docs", "", "2026-10-21T15:24:00Z", 70, 4, 91200, 3100, "")])
elif mode == "many":       # 14 runs, 5 tasks, 3 projects; three run-plan runs: two keep their steps, one does not
    R = [line("sample-repo", "csv-export-orders", "make-prompt", "quick", "2026-10-21T15:13:36Z", 144, 6, 186420, 9310, "14/14"),
         line("sample-repo", "csv-export-orders", "run-plan", "safe", "2026-10-21T15:16:00Z", 384, 22, 1203800, 21650, "5/6"),
         line("sample-repo", "csv-export-orders", "living-docs", "", "2026-10-21T15:24:00Z", 70, 4, 91200, 3100, ""),
         line("shop-api", "invoice-pdf", "make-prompt", "full", "2026-10-22T09:02:10Z", 410, 11, 402900, 18700, "13/14"),
         line("shop-api", "invoice-pdf", "run-plan", "aggressive", "2026-10-22T09:10:00Z", 1260, 61, 3980400, 64200, "8/9"),
         line("shop-api", "invoice-pdf", "living-docs", "", "2026-10-22T09:33:00Z", 95, 5, 110300, 4100, ""),
         line("shop-api", "login-rate-limit", "make-prompt", "quick", "2026-10-23T13:40:00Z", 130, 5, 150100, 7200, "14/14"),
         line("shop-api", "login-rate-limit", "run-plan", "safe", "2026-10-23T13:43:00Z", 520, 30, 1700500, 28800, "6/6"),
         line("docs-site", "docs-refresh", "make-prompt", "quick", "2026-10-24T08:00:00Z", 120, 4, 98000, 5200, "12/14"),
         line("docs-site", "docs-refresh", "run-plan", "off", "2026-10-24T08:03:00Z", 300, 18, 905000, 17100, "4/4"),
         line("docs-site", "docs-refresh", "living-docs", "", "2026-10-24T08:10:00Z", 60, 3, 70500, 2600, ""),
         line("docs-site", "nav-cleanup", "make-prompt", "quick", "2026-10-25T10:00:00Z", 100, 4, 88000, 4100, "14/14"),
         line("sample-repo", "csv-export-orders", "living-docs", "", "2026-10-26T11:00:00Z", 55, 3, 64000, 2400, ""),
         line("sample-repo", "nav-cleanup", "make-prompt", "quick", "2026-10-27T10:00:00Z", 90, 3, 80000, 3900, "14/14")]
    archive("sample-repo", "csv-export-orders", "2026-10-21T15:16:00Z")
    archive("shop-api", "invoice-pdf", "2026-10-22T09:10:00Z", edit=lambda r: r["units"].__setitem__(slice(None), r["units"][:5]))
    archive("docs-site", "docs-refresh", "2026-10-24T08:03:00Z", edit=lambda r: r["units"].__setitem__(slice(None), r["units"][:4]))   # login-rate-limit: no archive
    write(R)
elif mode == "paths":      # run-plan lines whose project_path cannot lead to a state folder, and one whose folder has no state folder yet
    gone = str(proj["docs-site"].resolve()) + "-gone"
    P = [("empty", ""), ("relative", "."), ("dotdot", str(proj["sample-repo"].resolve()) + "/../docs-site"), ("gone", gone), ("none", None), ("nostate", str(proj["shop-api"].resolve()))]
    rows = []
    for i, (name, pp) in enumerate(P):
        r = line("sample-repo", "path-" + name, "run-plan", "safe", f"2026-10-21T15:1{i}:00Z", 60, 2, 1000, 100, "1/1", path="x")
        if pp is None:
            del r["project_path"]
        else:
            r["project_path"] = pp
        rows.append(r)
    archive("sample-repo", "path-relative", "2026-10-21T15:11:00Z")   # what "." (the cwd) or ".." would reach, if a line's path were followed
    archive("docs-site", "path-dotdot", "2026-10-21T15:12:00Z")
    write(rows)
else:
    sys.exit("unknown mode " + mode)
PY
vuse() { VH="$D/$1"; mkdir -p "$VH"; VHP=$(HOME="$VH" py -c 'import os,pathlib; print(pathlib.Path(os.environ["HOME"]).as_posix())'); }   # VH: the HOME of this case; VHP: the HOME as the interpreter prints it
vmk() { py "$D/vbuild.py" "$1" "$(wp "$VH")" "$EXJ" "$(wp "$D/vp/sample-repo")" "$(wp "$D/vp/shop-api")" "$(wp "$D/vp/docs-site")"; }
vled() { ( cd "$D/vp/sample-repo" && env -u CLAUDE_PROJECT_DIR HOME="$VH" bash "$H/py.sh" "$H/ledger.py" "$@" < /dev/null ); }   # ledger.py in this case's HOME, as the Bash tool runs it: from the repo, CLAUDE_PROJECT_DIR unset
vexpect() { f="$1"; what="$2"; shift 2; vled "$@" | py "$D/norm.py" "$VHP" "$VKEY" > "$D/vact.txt"; if diff "$f" "$D/vact.txt" > "$D/vdiff.txt"; then echo "PASS $what"; else echo "FAIL $what:"; cat "$D/vdiff.txt"; exit 1; fi; }
vlines() { vled "$@" | tr -d '\r'; }   # the output with LF endings (Windows Python prints CRLF)
# p1, p2 (pins, green before and after the change: their text was taken from 0.7.6's ledger.py): --report and --receipts print what they printed
vuse vh1; vmk example
cat > "$D/pin-report.txt" <<'TXT'
ledger: 2 tasks  (~/.claude/smartuse/ledger.jsonl)
| when | project | skill | mode | task | min | fresh-in | cache-read | out | self-check |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-21T15:16 | sample-repo | make-prompt | quick | csv-export-orders | 2.4 | 33,556 | 152,864 | 9,310 | 14/14 |
| 2026-10-21T15:22 | sample-repo | run-plan | safe | csv-export-orders | 6.4 | 216,685 | 987,115 | 21,650 | 5/6 |
median total-in 695,110 (mostly cache reads) · median out 15,480 · total out 30,960
by skill/mode (median out): make-prompt/quick 9,310 (n=1) · run-plan/safe 21,650 (n=1)
TXT
vexpect "$D/pin-report.txt" "p1 --report on the fixture: the table and its two closing lines, byte for byte as 0.7.6 printed them (the report is now report_lines, which --view calls too)" --report
cat > "$D/pin-receipts.txt" <<'TXT'
receipts: csv-export-orders · dial safe · started 2026-10-21T15:16:00Z · closed · 6 steps  (~/.claude/smartuse/projects/<key>/runs/2026-10-21T15-16-00Z_csv-export-orders.json)
| # | step | tier | model | override | outcome | esc | verify | calls | in | out | check |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Route decision confirmed (path, colu | judgment | fable |  | pass |  |  |  |  |  | decisions.md: decision line written 2026 |
| 2 | src/routes/orders-export.js: toCsv() | build | fable |  | pass |  | no gaps | 5 | 110.7k | 2.7k | npm run lint: clean (exit 0); sanity row |
| 3 | Mount export router in src/server.js | build | fable |  | pass |  | no gaps | 5 | 107.6k | 1.2k | curl export.csv: 200 text/csv, header +  |
| 4 | tests/orders-export.test.js (unit +  | build | fable |  | pass |  | no gaps | 3 | 64.6k | 1.6k | npm test: Tests 6 passed, 6 total (2 sui |
| 5 | Docs: DEV.md + USER.md + README line | mechanical | haiku |  | pass |  |  | 3 | 72.8k | 4.5k | grep 'orders/export.csv' README.md:5 hit |
| 6 | Commit by path, move task folder, /l | judgment | fable |  | blocked |  |  |  |  |  | blocked: run-plan never commits; user's  |
steps 5 pass · 1 blocked · 0 open · agent tokens in 355.8k / out 10.0k · delegated out 10.0k (100% of agent output) on claude-fable-5-1, claude-haiku-5-5, claude-sonnet-5-5
TXT
vexpect "$D/pin-receipts.txt" "p2 --receipts <task> on the fixture: header, six step rows, closing line, byte for byte as 0.7.6 printed them (run_block is shared with --view)" --receipts csv-export-orders
# w1: look B on the fixture = the repo's example run as S1 rendered it
cat > "$D/gold-b.txt" <<'TXT'
ledger: 2 tasks  (~/.claude/smartuse/ledger.jsonl)
| when | project | skill | mode | task | min | fresh-in | cache-read | out | self-check |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-21T15:16 | sample-repo | make-prompt | quick | csv-export-orders | 2.4 | 33,556 | 152,864 | 9,310 | 14/14 |
| 2026-10-21T15:22 | sample-repo | run-plan | safe | csv-export-orders | 6.4 | 216,685 | 987,115 | 21,650 | 5/6 |
median total-in 695,110 (mostly cache reads) · median out 15,480 · total out 30,960
by skill/mode (median out): make-prompt/quick 9,310 (n=1) · run-plan/safe 21,650 (n=1)

receipts: csv-export-orders · dial safe · started 2026-10-21T15:16:00Z · closed · 6 steps  (~/.claude/smartuse/projects/<key>/runs/2026-10-21T15-16-00Z_csv-export-orders.json)
| # | step | tier | model | override | outcome | esc | verify | calls | in | out | check |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Route decision confirmed (path, colu | judgment | fable |  | pass |  |  |  |  |  | decisions.md: decision line written 2026 |
| 2 | src/routes/orders-export.js: toCsv() | build | fable |  | pass |  | no gaps | 5 | 110.7k | 2.7k | npm run lint: clean (exit 0); sanity row |
| 3 | Mount export router in src/server.js | build | fable |  | pass |  | no gaps | 5 | 107.6k | 1.2k | curl export.csv: 200 text/csv, header +  |
| 4 | tests/orders-export.test.js (unit +  | build | fable |  | pass |  | no gaps | 3 | 64.6k | 1.6k | npm test: Tests 6 passed, 6 total (2 sui |
| 5 | Docs: DEV.md + USER.md + README line | mechanical | haiku |  | pass |  |  | 3 | 72.8k | 4.5k | grep 'orders/export.csv' README.md:5 hit |
| 6 | Commit by path, move task folder, /l | judgment | fable |  | blocked |  |  |  |  |  | blocked: run-plan never commits; user's  |
steps 5 pass · 1 blocked · 0 open · agent tokens in 355.8k / out 10.0k · delegated out 10.0k (100% of agent output) on claude-fable-5-1, claude-haiku-5-5, claude-sonnet-5-5
TXT
vexpect "$D/gold-b.txt" "w1 --view on the fixture = look B: today's --report table, then the --receipts block of the run-plan row" --view
# w2: the block under the table IS what --receipts prints for that run (the same closing line), six step rows; the exit status is 0
vlines --view | sed -n '/^receipts:/,$p' > "$D/v-block.txt"; vlines --receipts csv-export-orders > "$D/r-block.txt"; rc=0; vled --view > /dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && cmp -s "$D/v-block.txt" "$D/r-block.txt" && [ "$(grep -c '^| [1-6] |' "$D/v-block.txt")" = 6 ] && grep -q '^steps 5 pass · 1 blocked · 0 open' "$D/v-block.txt" && echo "PASS w2 --view's run block equals --receipts <task> for the same run (six step rows, the same closing line), exit 0" || { echo "FAIL w2 (rc $rc):"; diff "$D/v-block.txt" "$D/r-block.txt" || true; exit 1; }
# w3 + w4: a run-plan line whose own archive is gone prints `steps: not kept (<archive>)`; the other run of the same task (another start time, with its own archive) is never shown in its place
vuse vh2; vmk nosteps
cat > "$D/gold-nosteps.txt" <<'TXT'
ledger: 3 tasks  (~/.claude/smartuse/ledger.jsonl)
| when | project | skill | mode | task | min | fresh-in | cache-read | out | self-check |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-21T15:16 | sample-repo | make-prompt | quick | csv-export-orders | 2.4 | 33,556 | 152,864 | 9,310 | 14/14 |
| 2026-10-21T15:22 | sample-repo | run-plan | safe | csv-export-orders | 6.4 | 216,685 | 987,115 | 21,650 | 5/6 |
| 2026-10-21T15:25 | sample-repo | living-docs |  | csv-export-orders | 1.2 | 16,416 | 74,784 | 3,100 |  |
median total-in 186,420 (mostly cache reads) · median out 9,310 · total out 34,060
by skill/mode (median out): make-prompt/quick 9,310 (n=1) · run-plan/safe 21,650 (n=1) · living-docs/ 3,100 (n=1)

steps: not kept (2026-10-21T15-16-00Z_csv-export-orders.json)
TXT
vexpect "$D/gold-nosteps.txt" "w3 a run-plan line with no archive of its own -> 'steps: not kept (<archive name>)' under the table, no block, nothing else changes" --view
vlines --view | grep -q '^steps: not kept' && ! vlines --view | grep -q "OTHER-RUN-STEP" && [ -f "$VH/.claude/smartuse/projects/$VKEY/runs/2026-10-22T09-00-00Z_csv-export-orders.json" ] && echo "PASS w4 a second archived run of the same task with another start time exists and is not shown under the first line (never the nearest run, never a guess)" || { echo "FAIL w4 the other run's step was shown"; exit 1; }
# w5: a half line, a line that is a list, a line with no task: the readable ones are shown (the line with no task too), `2 lines unreadable`, no traceback, exit 0
vuse vh3; vmk example
printf '%s\n' '{"ts":"2026-10-21T15:2' '[1, 2]' '{"ts":"2026-10-22T08:00:00Z","project":"sample-repo","skill":"living-docs","mode":"","started_at":"2026-10-22T08:00:00Z","duration_s":60,"tokens":{},"total_input":10,"total_output":5}' >> "$VH/.claude/smartuse/ledger.jsonl"
rc=0; vled --view > "$D/vo.txt" 2> "$D/ve.txt" || rc=$?; tr -d '\r' < "$D/vo.txt" > "$D/vo2.txt"
[ "$rc" = 0 ] && [ ! -s "$D/ve.txt" ] && grep -qx '2 lines unreadable' "$D/vo2.txt" && [ "$(grep -c '^| 2026' "$D/vo2.txt")" = 3 ] && grep -qF '| 2026-10-22T08:00 | sample-repo | living-docs |  |  | 1.0 | 0 | 0 | 5 |  |' "$D/vo2.txt" && [ "$(grep -c '^receipts:' "$D/vo2.txt")" = 1 ] && ! grep -q Traceback "$D/vo2.txt" "$D/ve.txt" && echo "PASS w5 a half line and a list line -> '2 lines unreadable'; the two runs and the line with no task are shown, the run's block too; no traceback, exit 0" || { echo "FAIL w5 (rc $rc):"; cat "$D/vo2.txt" "$D/ve.txt"; exit 1; }
printf '%s\n' '{"ts":"2026-10-22T08:05:00Z","project":"sample-repo","skill":"living-docs","task":"t","duration_s":"60","total_input":10,"total_output":5}' '{"ts":"2026-10-22T08:06:00Z","skill":"living-docs","task":"t","duration_s":60,"tokens":{"m":{"input":"x"}},"total_input":10,"total_output":5}' >> "$VH/.claude/smartuse/ledger.jsonl"
vlines --view | grep -qx '4 lines unreadable' && echo "PASS w5b a line whose duration is a string and a line whose tokens cannot be added are counted as unreadable too (not a traceback)" || { echo "FAIL w5b:"; vlines --view; exit 1; }
printf '%s\n' '{"ts":"2026-10-22T08:07:00Z","project":"sample-repo","skill":"living-docs","task":"t","duration_s":60,"total_input":10,"total_output":NaN}' >> "$VH/.claude/smartuse/ledger.jsonl"
vlines --view | grep -qx '5 lines unreadable' && echo "PASS w5c a NaN count is unreadable (the median would raise), not a traceback" || { echo "FAIL w5c:"; vlines --view; exit 1; }
# w6: a task name of 300 characters with an escape character and a newline: one row, the escape and the newline become spaces, the cap holds
vuse vh4; vmk example
py - "$VH/.claude/smartuse/ledger.jsonl" <<'PY'
import json, sys
r = json.loads(open(sys.argv[1], encoding="utf-8").read().splitlines()[0])
r.update(ts="2026-10-22T08:00:00Z", skill="living-docs", mode="", task="x" * 30 + "\x1b[31m\nred" + "y" * 262, project="sample\x1b[0m-repo")
open(sys.argv[1], "a", encoding="utf-8").write(json.dumps(r) + "\n")
PY
vlines --view > "$D/vo2.txt"
[ "$(grep -c '^| 2026' "$D/vo2.txt")" = 3 ] && ! grep -q "$(printf '\033')" "$D/vo2.txt" && grep -qF '| sample [0m-repo | living-docs |  | xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx [31m redy | 2.4 |' "$D/vo2.txt" && echo "PASS w6 a 300-character task with an escape and a newline: one row, escape and newline are spaces, cut at 40 characters; a project name is cleaned the same way" || { echo "FAIL w6:"; cat -A "$D/vo2.txt" | head -12; exit 1; }
# w7: --view N, --view <word>, --view all, both together; a word that matches nothing; a bad N or option is refused
vuse vh5; vmk many
rows() { vlines "$@" | grep -c '^| 2026'; }
[ "$(rows --view)" = 10 ] && [ "$(vlines --view | grep -E '^(receipts:|steps: not kept)' | cut -d' ' -f1-3)" = "$(printf '%s\n' 'receipts: invoice-pdf ·' 'steps: not kept' 'receipts: docs-refresh ·')" ] && vlines --view | grep -qx 'steps: not kept (2026-10-23T13-43-00Z_login-rate-limit.json)' && echo "PASS w7 --view: the last 10 of 14 runs; a block per run-plan row shown, in table order (two kept, one not kept)" || { echo "FAIL w7 default:"; vlines --view | cut -c1-120; exit 1; }
[ "$(rows --view 3)" = 3 ] && [ "$(vlines --view 3 | grep -c '^receipts:')" = 0 ] && [ "$(rows --view invoice-pdf)" = 3 ] && [ "$(vlines --view invoice-pdf | grep -c '^receipts: invoice-pdf')" = 1 ] && [ "$(rows --view all)" = 14 ] && [ "$(vlines --view all | grep -c '^receipts:')" = 3 ] && [ "$(vlines --view all | grep -c '^steps: not kept')" = 1 ] && [ "$(rows --view 2 docs)" = 2 ] && [ "$(vlines --view 2 docs | grep -c '^receipts: docs-refresh')" = 1 ] && echo "PASS w7 --view 3 (the last three rows) · --view <task word> (only that task's three rows and its block) · --view all (14 rows, three blocks, one 'not kept') · --view 2 docs (the last two runs of tasks holding 'docs')" || { echo "FAIL w7 N / word / all"; exit 1; }
OUT=$(vlines --view nonesuch); rc=0; vled --view 0 > /dev/null 2> "$D/ve0.txt" || rc=$?; rc2=0; vled --view --json > /dev/null 2> "$D/ve1.txt" || rc2=$?
echo "$OUT" | grep -qx 'no run of a task holding "nonesuch"' && [ "$rc" = 1 ] && [ "$rc2" = 1 ] && grep -q '^view refused: N must be 1 or more' "$D/ve0.txt" && grep -q '^view refused: unknown option' "$D/ve1.txt" && echo "PASS w7 a word that matches nothing says so; --view 0 and an option it does not know are refused (exit 1, one line on stderr)" || { echo "FAIL w7 refusals (rc $rc $rc2):"; echo "$OUT"; cat "$D/ve0.txt" "$D/ve1.txt"; exit 1; }
# w8: an empty and a missing ledger print today's two lines, as --report does; nothing is made
vuse vh6; OUT=$(vlines --view); [ "$OUT" = "ledger: empty (no task recorded yet)" ] && [ "$OUT" = "$(vlines --report)" ] && [ -z "$(ls -A "$VH")" ] || { echo "FAIL w8 missing ledger: '$OUT'"; exit 1; }
vuse vh7; mkdir -p "$VH/.claude/smartuse"; : > "$VH/.claude/smartuse/ledger.jsonl"; OUT=$(vlines --view); [ "$OUT" = "ledger: empty" ] && [ "$OUT" = "$(vlines --report)" ] && echo "PASS w8 a missing and an empty ledger print --report's own two lines (ledger: empty (no task recorded yet) / ledger: empty); nothing is made" || { echo "FAIL w8 empty ledger: '$OUT'"; exit 1; }
# w9: a run in progress (this project's routing.json, active) and no ledger line for it yet: a last block `running now`; a word that does not name it leaves it out
vuse vh8; vled --put routing.json '{"active":true,"task":"live-task","dial":"safe","started_at":"2026-10-28T10:00:00Z","units":[{"id":1,"title":"decide","tier":"judgment","model":"session","status":"pass"},{"id":2,"title":"build it","tier":"build","model":"opus","status":"running"},{"id":3,"title":"test it","tier":"build","model":"opus","status":"pending"}]}' > /dev/null
vlines --view > "$D/vo2.txt"
[ "$(sed -n 1,3p "$D/vo2.txt" | tr '\n' '|')" = 'ledger: empty (no task recorded yet)||running now|' ] && grep -q '^receipts: live-task · dial safe · started 2026-10-28T10:00:00Z · active · 3 steps' "$D/vo2.txt" && [ "$(grep -c '^| [1-3] |' "$D/vo2.txt")" = 3 ] && grep -q '^steps 1 pass · 0 blocked · 2 open' "$D/vo2.txt" && ! vlines --view nomatch | grep -q 'running now' && vlines --view live | grep -qx 'running now' && echo "PASS w9 an active routing.json and no ledger line: 'running now' and its three steps; a word that does not name the run leaves the block out, one that does keeps it" || { echo "FAIL w9:"; cat "$D/vo2.txt"; exit 1; }
# w10 + w11: --view writes nothing (every file under the HOME and the projects keeps its bytes; no folder is made for a project_path that has none), and a project_path that is empty, missing, relative, holds `..`, or names a folder that is gone gives `steps: not kept`
vuse vh9; vmk paths; NOSTATE="$VH/.claude/smartuse/projects/$(key "$(wp "$D/vp/shop-api")")"
vled --view > /dev/null; S0=$(snap "$VH"); S1=$(snap "$D/vp")   # the first call may write py.sh's interpreter hint; the snapshots come after it
vlines --view > "$D/vo2.txt"; vlines --view all > /dev/null; vlines --view path-gone > /dev/null; vlines --view 2 > /dev/null; rc=0; vled --view > /dev/null 2>&1 || rc=$?
grep -q '^ledger: 6 tasks' "$D/vo2.txt" && [ "$(snap "$VH")" = "$S0" ] && [ "$(snap "$D/vp")" = "$S1" ] && [ ! -e "$NOSTATE" ] && echo "PASS w10 five --view calls: every file under the HOME and the projects has the same hash, and no state folder was made for a project_path that had none" || { echo "FAIL w10 something was written or made"; exit 1; }
[ "$rc" = 0 ] && [ "$(grep -c '^steps: not kept' "$D/vo2.txt")" = 6 ] && ! grep -q '^receipts:' "$D/vo2.txt" && ! grep -q Traceback "$D/vo2.txt" && echo "PASS w11 a project_path that is empty, missing, '.', holds '..', is gone, or has no state folder -> 'steps: not kept' (6 of 6), never another project's run; no exception, exit 0" || { echo "FAIL w11 (rc $rc):"; cat "$D/vo2.txt"; exit 1; }
# v2: the ledger skill's own `!` line (read from its SKILL.md, $ARGUMENTS filled in as the shell would) through the launcher on the example fixture: no words and `2` both start with look B's first line, exit 0
vuse vh10; vmk example; SK="$H/../skills/ledger/SKILL.md"
BANG=$(sed -n 's/^!`\(.*\)`$/\1/p' "$SK" | tr -d '\r')
vbang() { ( cd "$D/vp/sample-repo" && env -u CLAUDE_PROJECT_DIR HOME="$VH" CLAUDE_PLUGIN_ROOT="$(cd "$H/.." && pwd)" ARGUMENTS="$1" bash -c "ARGUMENTS=\"\$ARGUMENTS\"; set -f; eval \"\${BANG_CMD}\"" < /dev/null ); }
case "$BANG" in *'hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --view $ARGUMENTS || true') ;; *) echo "FAIL v2 the ledger skill's ! line is not 'py.sh ledger.py --view \$ARGUMENTS || true': $BANG"; exit 1;; esac
export BANG_CMD="$BANG"; V0=$(vbang "" | tr -d '\r'); V2=$(vbang "2" | tr -d '\r'); export -n BANG_CMD
[ "$(printf '%s\n' "$V0" | sed -n 1p | cut -c1-18)" = "ledger: 2 tasks  (" ] && [ "$(printf '%s\n' "$V2" | sed -n 1p | cut -c1-18)" = "ledger: 2 tasks  (" ] && printf '%s\n' "$V0" | grep -q '^receipts: csv-export-orders' && printf '%s\n' "$V2" | grep -q '^| 2026-10-21T15:22 ' && echo "PASS v2 the ledger skill's ! line, with no words and with 2, through py.sh on the example fixture: look B's first line, then the run-plan run's steps block" || { echo "FAIL v2 ! line run:"; printf '%s\n' "$V0" | head -5; printf '%s\n' "$V2" | head -5; exit 1; }
echo "ALL PASS"
