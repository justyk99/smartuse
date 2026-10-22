#!/usr/bin/env bash
# fake-claude.sh — the dry-run shim for bench/ab.sh. Stands in for the `claude` binary (CLAUDE_BIN=bench/fake-claude.sh):
# parses `-p "<prompt>"`, leaves behind what the real skills would (a task.md for make-prompt, an archived run JSON under
# ~/.claude/smartuse/projects/<basename of cwd>/runs/ for run-plan) and prints the ONE JSON object `claude -p
# --output-format json` prints. Deterministic, no model, nothing spent. The numbers are fixtures, not measurements:
# off = everything on the session model (~9k agent out, $3.70) · safe = build on the session model + verify on sonnet,
# mechanical on haiku (~8k, $3.40) · aggressive = build on sonnet, mechanical on haiku (~6k, $2.10); 4 steps, one blocked.
set -u
PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--print) if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then PROMPT=$2; shift 2; else shift; fi ;;
    --version) echo "fake-claude 0.0.0 (bench/fake-claude.sh dry-run shim)"; exit 0 ;;
    --plugin-dir|--permission-mode|--output-format|--max-turns|--max-budget-usd|--model) shift 2 ;;
    -*) shift ;;
    *) [ -z "$PROMPT" ] && PROMPT=$1; shift ;;
  esac
done

case "$PROMPT" in
  /smartuse:make-prompt*)
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
    printf '%s\n' '{"total_cost_usd":1.5,"num_turns":6,"duration_ms":150000,"result":"Prompt saved: .task/ACTIVE/csv-export/task.md\nSelf-check: 14/14"}'
    ;;
  /smartuse:run-plan*)
    # shellcheck disable=SC2086
    set -- $PROMPT; TASK=${2:-}
    if [ -z "$TASK" ] || [ ! -f "$TASK" ]; then
      printf '{"total_cost_usd":0.05,"num_turns":1,"duration_ms":5000,"result":"run `make-prompt` first: no task.md at %s"}\n' "$TASK"
      exit 0
    fi
    case "$PROMPT" in
      *"--routing aggressive"*) DIAL=aggressive ;;
      *"--routing off"*)        DIAL=off ;;
      *)                        DIAL=safe ;;
    esac
    case "$DIAL" in
      off)        COST=3.7; M_BUILD=session-model; AM_BUILD='"session-model"';           O_BUILD=5000; I_BUILD=210000; M_MECH=session-model; O_MECH=4000 ;;
      safe)       COST=3.4; M_BUILD=session-model; AM_BUILD='"session-model", "sonnet"'; O_BUILD=4500; I_BUILD=200000; M_MECH=haiku;         O_MECH=3500 ;;
      aggressive) COST=2.1; M_BUILD=sonnet;        AM_BUILD='"sonnet"';                  O_BUILD=3200; I_BUILD=180000; M_MECH=haiku;         O_MECH=2800 ;;
    esac
    SD="$HOME/.claude/smartuse/projects/$(basename "$PWD")"; mkdir -p "$SD/runs"
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
     "files": ["src/routes/orders-export.js", "src/server.js", "tests/orders-export.test.js"]},
    {"id": 3, "title": "Docs: DEV.md + USER.md + README line", "tier": "mechanical", "model": "$M_MECH",
     "why": "doc fill from a fixed spec; check is a grep for the exact path", "budget_turns": 10, "check": "grep 'orders/export.csv' README.md: hit",
     "blocked_by": null, "status": "pass", "override": null, "escalated": false, "verify": null,
     "agent_calls": 3, "agent_input": 70000, "agent_output": $O_MECH, "agent_models": ["$M_MECH"], "agents": ["a-docs"],
     "files": ["docs/features/csv-export/DEV.md", "docs/features/csv-export/USER.md", "README.md"]},
    {"id": 4, "title": "Commit by path, move task folder, /living-docs", "tier": "judgment", "model": "session-model",
     "why": "run-plan never commits; the user's commit procedure does", "budget_turns": 0, "check": "blocked: run-plan never commits",
     "blocked_by": "rule: no commits from run-plan", "status": "blocked", "override": null, "escalated": false, "verify": null, "files": []}
  ],
  "finished_at": "2026-01-01T00:06:20Z",
  "closed_at": "2026-01-01T00:06:20Z"
}
JSON
    printf '{"total_cost_usd":%s,"num_turns":20,"duration_ms":380000,"result":"done"}\n' "$COST"
    ;;
  *)
    printf '{"total_cost_usd":0.01,"num_turns":1,"duration_ms":1000,"result":"fake-claude: unknown prompt"}\n'
    ;;
esac
