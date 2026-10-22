#!/usr/bin/env bash
# fake-claude.sh — the dry-run shim for bench/ab.sh. Stands in for the `claude` binary (CLAUDE_BIN=bench/fake-claude.sh):
# parses `-p "<prompt>"` and `--model`, leaves behind what the real skills would (a task.md for make-prompt, an archived run
# JSON under ~/.claude/smartuse/projects/<basename of cwd>/runs/ for run-plan) and prints the ONE JSON object `claude -p
# --output-format json` prints, including `modelUsage` (keyed by the models that "ran" in the session) and `subagent_stats`.
# Deterministic, no model, nothing spent. The numbers are fixtures, not measurements:
#   off = everything on the session model (9k agent out, $3.70) · safe = build on the session model + verify on sonnet,
#   mechanical on haiku (8k, $3.40) · aggressive = build on sonnet, mechanical on haiku (6k, $2.10); 4 steps, one blocked.
#   Every step that ran agents carries `agent_by_model` ({model: {calls, input, output}}) the way the 0.4.0 hook writes it,
#   next to the older `agent_output` + `agent_models` pair.
#   Ask 2 on dial off (cwd basename ab-2-off-*) does NO work: it stops on NEEDS YOU with 0 steps passed and no agent, the way
#   A/B run 1's off and safe rows did, so the report's no-work rule has a row to act on.
#   Session model: `--model X` is echoed back as the model of every session. Without --model the shim drifts the way A/B run 1
#   did (kickoff on claude-fable-5-1, run-plan sessions on claude-opus-5-5), so the report's "models differ" flag is exercised.
set -u
PROMPT=""; MODEL=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--print) if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then PROMPT=$2; shift 2; else shift; fi ;;
    --version) echo "fake-claude 0.0.0 (bench/fake-claude.sh dry-run shim)"; exit 0 ;;
    --model) MODEL=${2:-}; shift 2 ;;
    --plugin-dir|--permission-mode|--output-format|--max-turns|--max-budget-usd) shift 2 ;;
    -*) shift ;;
    *) [ -z "$PROMPT" ] && PROMPT=$1; shift ;;
  esac
done
# one entry of claude's modelUsage: model, input, output, cache read, cache creation, cost
mu() { printf '"%s":{"inputTokens":%s,"outputTokens":%s,"cacheReadInputTokens":%s,"cacheCreationInputTokens":%s,"costUSD":%s}' "$1" "$2" "$3" "$4" "$5" "$6"; }
# one entry of a step's agent_by_model: model, calls, input, output
bm() { printf '"%s": {"calls": %s, "input": %s, "output": %s}' "$1" "$2" "$3" "$4"; }

case "$PROMPT" in
  /smartuse:make-prompt*)
    SM=${MODEL:-claude-fable-5-1}
    mkdir -p .task/ACTIVE/csv-export
    cat > .task/ACTIVE/csv-export/task.md <<'MD'
# csv-export — kickoff (dry-run fixture written by bench/fake-claude.sh, not by a model)
## 1. Ask
add a CSV export of orders: GET /orders/export.csv returns every order as RFC 4180 CSV, with a test.
## 4. Constraints and rabbit holes
Never edit src/db.js or src/routes/orders.js (other owner); the /:id route shadows export.csv; escape commas and quotes.
## 5. Deliverables
- [ ] 1. Route decision confirmed (path, columns, no orders.js edit)
- [ ] 2. src/routes/orders-export.js + mount in src/server.js + tests/orders-export.test.js
- [ ] 3. Docs: DEV.md + USER.md + README line
## 8. Verification: npm test green; curl /orders/export.csv returns the header + 2 rows
MD
    printf '{"total_cost_usd":1.5,"num_turns":6,"duration_ms":150000,"result":"Prompt saved: .task/ACTIVE/csv-export/task.md\\nSelf-check: 14/14","modelUsage":{%s},"subagent_stats":{"spawned":0,"completed":0}}\n' \
      "$(mu "$SM" 130 10400 149000 49000 1.5)"
    ;;
  /smartuse:run-plan*)
    # shellcheck disable=SC2086
    set -- $PROMPT; TASK=${2:-}
    if [ -z "$TASK" ] || [ ! -f "$TASK" ]; then
      printf '{"total_cost_usd":0.05,"num_turns":1,"duration_ms":5000,"result":"run `make-prompt` first: no task.md at %s"}\n' "$TASK"
      exit 0
    fi
    SM=${MODEL:-claude-opus-5-5}
    case "$PROMPT" in
      *"--routing aggressive"*) DIAL=aggressive ;;
      *"--routing off"*)        DIAL=off ;;
      *)                        DIAL=safe ;;
    esac
    SD="$HOME/.claude/smartuse/projects/$(basename "$PWD")"; mkdir -p "$SD/runs"
    case "$(basename "$PWD")" in
      ab-2-off-*)   # no work: NEEDS YOU before any step, every unit blocked, no agent ran (A/B run 1's off and safe rows)
        cat > "$SD/runs/2026-01-01T00-00-00Z_csv-export.json" <<JSON
{
  "active": false,
  "task": "csv-export",
  "dial": "$DIAL",
  "started_at": "2026-01-01T00:00:00Z",
  "until_done": true,
  "needs_human": "Row shape: one CSV row per order (assumed) or one row per line item? Nothing was built.",
  "units": [
    {"id": 1, "title": "Route decision confirmed (path, columns, no orders.js edit)", "tier": "judgment", "model": "session-model",
     "why": "user gate + other developer's file", "budget_turns": 0, "check": "decisions.md: decision line written",
     "blocked_by": "row shape unanswered", "status": "blocked", "override": null, "escalated": false, "verify": null},
    {"id": 2, "title": "src/routes/orders-export.js + mount + tests", "tier": "build", "model": "session-model",
     "why": "well-specified change with a runnable check (npm test)", "budget_turns": 15, "check": "npm test: Tests 6 passed, 6 total",
     "blocked_by": "row shape unanswered; unit 1", "status": "blocked", "override": null, "escalated": false, "verify": null},
    {"id": 3, "title": "Docs: DEV.md + USER.md + README line", "tier": "mechanical", "model": "session-model",
     "why": "doc fill from a fixed spec; check is a grep for the exact path", "budget_turns": 10, "check": "grep 'orders/export.csv' README.md: hit",
     "blocked_by": "row shape unanswered; unit 2", "status": "blocked", "override": null, "escalated": false, "verify": null},
    {"id": 4, "title": "Commit by path, move task folder, /living-docs", "tier": "judgment", "model": "session-model",
     "why": "run-plan never commits; the user's commit procedure does", "budget_turns": 0, "check": "blocked: run-plan never commits",
     "blocked_by": "rule: no commits from run-plan", "status": "blocked", "override": null, "escalated": false, "verify": null}
  ],
  "closed_at": "2026-01-01T00:00:48Z"
}
JSON
        printf '{"total_cost_usd":0.35,"num_turns":6,"duration_ms":48000,"result":"**NEEDS YOU:** one CSV row per order (assumed) or one row per line item? Nothing was built: all 4 steps are blocked and no agent ran.","modelUsage":{%s},"subagent_stats":{"spawned":0,"completed":0}}\n' \
          "$(mu "$SM" 12 4000 196000 27000 0.35)"
        exit 0 ;;
    esac
    # M_* = the model name the session writes on the step (short, as the real plans do); the hook's keys are full ids.
    case "$DIAL" in
      off)        COST=3.7; O_BUILD=5000; I_BUILD=210000; O_MECH=4000
                  M_BUILD=session-model; AM_BUILD="\"$SM\"";                        BM_BUILD=$(bm "$SM" 8 210000 5000)
                  M_MECH=session-model;  MM_MECH=$SM
                  MU="$(mu "$SM" 20 12000 400000 50000 3.7)" ;;
      safe)       COST=3.4; O_BUILD=4500; I_BUILD=200000; O_MECH=3500
                  M_BUILD=session-model; AM_BUILD="\"$SM\", \"claude-sonnet-5-5\""; BM_BUILD="$(bm "$SM" 5 130000 3000), $(bm claude-sonnet-5-5 3 70000 1500)"
                  M_MECH=haiku;          MM_MECH=claude-haiku-5-5
                  MU="$(mu "$SM" 20 6000 300000 40000 2.9),$(mu claude-sonnet-5-5 5 1500 60000 10000 0.3),$(mu claude-haiku-5-5 5 3500 60000 10000 0.2)" ;;
      aggressive) COST=2.1; O_BUILD=3200; I_BUILD=180000; O_MECH=2800
                  M_BUILD=sonnet;        AM_BUILD='"claude-sonnet-5-5"';            BM_BUILD=$(bm claude-sonnet-5-5 8 180000 3200)
                  M_MECH=haiku;          MM_MECH=claude-haiku-5-5
                  MU="$(mu "$SM" 20 3000 250000 30000 1.6),$(mu claude-sonnet-5-5 10 3200 150000 50000 0.4),$(mu claude-haiku-5-5 5 2800 60000 10000 0.1)" ;;
    esac
    cat > "$SD/runs/2026-01-01T00-00-00Z_csv-export.json" <<JSON
{
  "active": false,
  "task": "csv-export",
  "dial": "$DIAL",
  "started_at": "2026-01-01T00:00:00Z",
  "until_done": true,
  "units": [
    {"id": 1, "title": "Route decision confirmed (path, columns, no orders.js edit)", "tier": "judgment", "model": "session-model",
     "why": "user gate + other developer's file", "budget_turns": 0, "check": "decisions.md: decision line written",
     "blocked_by": null, "status": "pass", "override": null, "escalated": false, "verify": null,
     "files": [".task/ACTIVE/csv-export/decisions.md"]},
    {"id": 2, "title": "src/routes/orders-export.js + mount + tests", "tier": "build", "model": "$M_BUILD",
     "why": "well-specified change with a runnable check (npm test)", "budget_turns": 15, "check": "npm test: Tests 6 passed, 6 total",
     "blocked_by": null, "status": "pass", "override": null, "escalated": false, "verify": "no gaps",
     "agent_calls": 8, "agent_input": $I_BUILD, "agent_output": $O_BUILD, "agent_models": [$AM_BUILD], "agents": ["a-build", "a-verify"],
     "agent_by_model": {$BM_BUILD},
     "files": ["src/routes/orders-export.js", "src/server.js", "tests/orders-export.test.js"]},
    {"id": 3, "title": "Docs: DEV.md + USER.md + README line", "tier": "mechanical", "model": "$M_MECH",
     "why": "doc fill from a fixed spec; check is a grep for the exact path", "budget_turns": 10, "check": "grep 'orders/export.csv' README.md: hit",
     "blocked_by": null, "status": "pass", "override": null, "escalated": false, "verify": null,
     "agent_calls": 3, "agent_input": 70000, "agent_output": $O_MECH, "agent_models": ["$MM_MECH"], "agents": ["a-docs"],
     "agent_by_model": {$(bm "$MM_MECH" 3 70000 "$O_MECH")},
     "files": ["docs/features/csv-export/DEV.md", "docs/features/csv-export/USER.md", "README.md"]},
    {"id": 4, "title": "Commit by path, move task folder, /living-docs", "tier": "judgment", "model": "session-model",
     "why": "run-plan never commits; the user's commit procedure does", "budget_turns": 0, "check": "blocked: run-plan never commits",
     "blocked_by": "rule: no commits from run-plan", "status": "blocked", "override": null, "escalated": false, "verify": null, "files": []}
  ],
  "finished_at": "2026-01-01T00:06:20Z",
  "closed_at": "2026-01-01T00:06:20Z"
}
JSON
    printf '{"total_cost_usd":%s,"num_turns":20,"duration_ms":380000,"result":"done","modelUsage":{%s},"subagent_stats":{"spawned":3,"completed":3}}\n' "$COST" "$MU"
    ;;
  *)
    printf '{"total_cost_usd":0.01,"num_turns":1,"duration_ms":1000,"result":"fake-claude: unknown prompt"}\n'
    ;;
esac
