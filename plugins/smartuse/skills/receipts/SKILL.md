---
name: receipts
description: Show the receipt per plan step of the latest run-plan run (or a named task) — step · tier · model · user override · outcome · escalation · verification · agent calls and tokens · check — and the agent-output share by model. Use when the user asks "what ran where", "show the receipts", "which model did step 3", "did the review find gaps", "how much did the plan cost per step", or wants the table for a write-up.
argument-hint: "[task name | all]"
allowed-tools: Bash(python3 *)
---

# receipts — one receipt per plan step (deterministic, 0 model tokens to compute)

!`python3 "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --receipts ${1:-} || true`

Explain the table in ≤ 5 lines: one row = one plan step from the kickoff's deliverables; `tier/model` is what run-plan chose and why, `override` is the user's retier (`from→to`), `outcome` is pass / fail / blocked / pending, `esc` marks the one escalation, `verify` is the fresh-agent review's verdict, `calls · in · out` are the agent's real API calls and tokens attached by the SubagentStop hook (never estimated). The summary line's `agent out by model: fable 40% · haiku 45% · sonnet 13%` is each model's share of all agent output tokens, largest first (names shortened, `claude-haiku-5-5` → `haiku`) — quote it as printed, never compute your own split; a run archived before 0.4.0 shows the older `delegated out …` form instead. For a script or a write-up that needs the raw numbers, `python3 "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --receipts [task|all] --json` prints the same run(s) as JSON only (the steps verbatim plus `totals.input / output / by_model`), nothing to explain in that mode. Name the outlier row if any, and the `needs_human` question if one is set. Data: `~/.claude/smartuse/projects/<repo>/routing.json` (the active or latest run) and `runs/` (closed runs, archived by the Stop hook). A step with no tokens ran in the session (judgment) or never ran.
