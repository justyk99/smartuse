---
name: run-plan
description: Execute a saved kickoff (the task.md that make-prompt wrote) with a tier plan and receipts. The session model tags each deliverable judgment / build / mechanical / verify, shows a routing table as a DRY RUN (unit → tier → model → why → turn budget) and waits for "go"; then runs units in the FOREGROUND through the Agent tool with the model per tier (never above the session's model), writes a receipt per unit, verifies every delegated result with a fresh agent, and closes with a receipts summary. Dial: --routing off | safe (default) | aggressive. `--until-done` = the lazy-CEO loop: no "go" between batches, the Stop gate refuses to end the turn while units or the repo check are unfinished, stops only for a real human question, a double failure, a rule gate or the cap. Use when the user says "run the plan", "execute the kickoff", "start deliverable 1", or types the run-plan line that make-prompt's hand-off printed.
argument-hint: "<task folder or task.md> [--routing off|safe|aggressive] [--units N] [--yes] [--until-done]"
allowed-tools: Read, Grep, Glob, Agent, Write, Edit, Bash(bash *), Bash(ls *), Bash(cat *), Bash(date *), Bash(mkdir *), Bash(git diff *), Bash(git status *), Bash(svn diff *), Bash(svn status *)
disable-model-invocation: true
---

# run-plan — tiered execution with a receipt per plan step (v0.2, 2026-10-21)

Why: the kickoff names the deliverables; this skill decides who does each one and proves what it cost. **One receipt per plan step**: tier · model · why · the user's override · outcome · escalation · verification · the agent's real tokens — the thing no router shows. The dial exists because lower models only pay off on small, checkable units.

Manual-only on purpose (`disable-model-invocation: true`): it spends plan usage, so only the user starts it with `/run-plan`. Skills that finish a kickoff should SUGGEST it, never call it.

## Live context
- Now: !`date -u +%FT%TZ || true` · session model: the model answering this turn (never spawn an agent on a stronger one)
- Arguments: `$ARGUMENTS` — a task folder or task.md; `--routing off|safe|aggressive` (default safe); `--units N` (default 3 per "go"); `--yes` skips the dry-run wait (headless only); `--until-done` = run every unit without waiting, keep going until done or a stop reason (see § 3b); it implies `--yes` — the dry-run table is printed, not waited on.
- Repo check command: from the adapter `check:` in `.claude/smartuse.local.md` (human-written; the hook never reads it from routing.json) — required for `--until-done`; without it the gate only tracks unit status. The gate accepts exactly these shapes, verbatim: `npm test` · `pnpm test` · `yarn test` · `bun test` · `pytest [paths]` · `make test` · `make check` · `cargo test` · `go test ./...` · `dotnet test` · `mvn test` · `gradle test`, or a `bash <script-in-repo>` the human pinned with `until-done.py --trust` (Linux/macOS only — pins are never trusted on Windows). Anything else is refused and the gate says so: `npm run x`, `npx …`, `python -m pytest`, flags, pipes, `&&`.
- State dir (where pending.json / routing.json / receipts.jsonl go): !`bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --state-dir --create || true`

## 0. Read the kickoff
Read task.md: § 5 deliverables (the units), § 4 constraints and rabbit holes (restated in every brief), § 7 open questions, § 8 verification. No task.md → "run `make-prompt` first" and stop.

**Open questions are not all blockers.** make-prompt writes a kickoff that assumes and lets the user correct by exception, so:
- A question whose answer the kickoff already gives as an `assumed:` default (a route, a column set, a date, a file layout) is **answered for now**: proceed on the default, write one dated line in `decisions.md` ("proceeding on assumed <X>; correct by exception"), and list it at the end under **Confirm**, not under NEEDS YOU.
- A question with **no default**, or one in a rule-gate area (money, security, shared servers or procedures, another person's file that the plan would edit), **blocks** the units that depend on it — say so, do not guess.
- Never block every unit on a question the kickoff has a default for. A run that ends with 0 steps done and a NEEDS YOU about an assumed value is a failed run.

## 1. Tier each unit (the session model decides, never a hook or a keyword rule)
| Tier | What belongs here | Who runs it |
|---|---|---|
| **judgment** | design options, root cause, anything on money / security / shared procedures / other people's files, writing or changing the plan | the session model, in this conversation (no agent) |
| **build** | a well-specified change with a runnable check (test, build, script, screenshot compare) | `safe`: the session model via a fresh foreground agent · `aggressive`: one tier below the session model |
| **mechanical** | greps, caller inventories, file lists, doc updates, test-data generation, key or translation checks, formatting | the cheapest model your plan offers (`haiku` where available) via a foreground agent |
| **verify** | review a delegated unit's output against its spec, gaps only | a fresh agent, one tier below the session model (`sonnet` where available) |
`--routing off`: every unit on the session model, receipts still written — this is the A/B baseline. Rules: a unit without a runnable check is never `mechanical`; nothing is routed to a model stronger than the session's; a blocked unit stays blocked.

## 2. Dry run (always shown, then WAIT for "go" unless --yes or --until-done)
Write `routing.json` in the state dir from the live context (never inside the repo; if that line is empty, run its command yourself — it prints the dir and creates it): `{"active":true,"task":"<name>","dial":"safe","started_at":"<now>","units":[{"id":1,"title":"…","tier":"mechanical","model":"haiku","why":"<one line>","budget_turns":15,"check":"<the runnable check>","blocked_by":null,"status":"pending","override":null,"escalated":false,"verify":null}]}` and print the same as a table: `# · unit · tier · model · why · budget · check`. Then: `Say "go" to run the first <N>, "go all", or "retier 3 build" to change a row.` Nothing runs before that — except with `--until-done`, which implies `--yes`: print the table, then go straight to § 3b. A retier is recorded on the unit, never silently applied: `"override": {"from":"mechanical","to":"build","by":"user","at":"<now>"}` and `tier` / `model` updated — the receipt shows `mechanical→build`.

## 3. Execute, one unit at a time, FOREGROUND
For each unit in order:
1. Set the unit's `"status": "running"` in routing.json (only one unit may be running at a time — that is how the SubagentStop hook knows which plan step the agent's tokens belong to). Spawn ONE Agent (foreground — the user sees the task card and tool count) with `model` per the table and a brief of ≤ 40 lines: the unit's spec and check · the constraints + rabbit holes from § 4 · the files it may touch (and only those) · "you cannot ask questions: write `unknown: <what> → <who>` instead" · "report: what you did, the check's output verbatim, files changed, unknowns" · the turn budget.
2. On return, set the unit's `status` (`pass` · `fail` · `blocked`), `check` (first line of the check output) and `files` in routing.json, and append the same as a receipt line to `receipts.jsonl` in the state dir from the live context: `{"ts","unit":1,"title","tier","model","outcome":"pass|fail|blocked","check":"…","escalated":false,"files":[…]}`. The SubagentStop hook has already attached the agent's real calls and tokens to the running unit (`agent_calls`, `agent_input`, `agent_output`, `agent_models`, `agent_by_model`, `agents`) and written its own line — never estimate tokens yourself, never overwrite those fields (read routing.json, change your fields, write it back).
3. `fail`, or a blocking `unknown:` → **escalate once**: set `status` back to `running`, re-run the unit one tier up (never above the session model) with the failure pasted in; record `"escalated":true` and the new `model` (the receipt keeps both agents' tokens on the step). Still failing or blocked → stop the batch and go to § 4 Close anyway (the receipts and the ledger line must exist even for a blocked run); do not loop.
4. **Verify** every delegated `build` unit: set the unit `running` again, then a fresh agent (verify tier) gets the diff (`git diff` / `svn diff` of the unit's files) + the unit's spec: "list only gaps that affect correctness or the stated spec; no style". Record the verdict on the unit: `"verify": "no gaps" | "gaps fixed" | "gaps open"`. Gaps → fix on the build tier once → re-verify once. Judgment units are verified by the user, not by an agent (`verify` stays null).
5. After each unit print ONE line: `unit 2/5 done · mechanical/haiku · check passed · next: unit 3 (build)`. That line is the visibility rule — never run silently.
Stop after N units (default 3) and ask "go" again, so the user can read the receipts between batches.

## 3b. `--until-done` — the lazy-CEO loop
Write `"until_done": true` and a `"status": "pending"` on every unit into routing.json before the first unit. The check command is read by the gate from the human-written adapter (`check:` in `.claude/smartuse.local.md`) — you cannot set or change it from routing.json; if the adapter has none, the gate only tracks unit status. Then:
1. Run units in order with no "go" between batches. After each unit set its `status` (`pass` · `fail` · `blocked`) in routing.json and print the one-line progress message.
2. The `until-done` Stop hook refuses to end the turn while any unit is pending / running / failed or while the check command fails, and tells you what is left. Keep working; do not argue with the gate.
3. **Stop reasons — the only ways out:** (a) every unit is pass or blocked AND the check passes; (b) a unit needs the human for a question with **no assumed default** (or a rule gate): write the exact question into routing.json as `"needs_human": "<question>"` and make it the FIRST line of your final message (`NEEDS YOU: …`) — an assumed default is not a stop reason, see § 0; (c) a unit failed twice (escalation used) → mark it `blocked`, record why, continue with units that do not depend on it; (d) a rule gate (a file owned by someone else, a shared server, money or security paths) → `needs_human`; (e) the gate has blocked 6 times → it lets you stop; say what is left.
4. Never commit. The final message: `NEEDS YOU` line if any (real blockers only), then the receipts table, then **Confirm** (the assumed defaults you proceeded on, one line each), then "what the human should look at first".
In an interactive session the user may also set `/goal <§ 8 acceptance>`; in headless use the CLI caps and the permission flag a real run needs (agents, file writes and the hooks' own commands): `claude -p "/smartuse:run-plan <task.md> --until-done" --permission-mode bypassPermissions --max-budget-usd N --max-turns M` — bash-guard still fires in bypass mode.

## 4. Close (always — after a finished batch, a stop, or a block)
- Tick the units' boxes in task.md; add a dated line to `decisions.md` / `## Decisions` for every escalation or retier.
- Print the receipts table with `bash "${CLAUDE_PLUGIN_ROOT}/hooks/py.sh" "${CLAUDE_PLUGIN_ROOT}/hooks/ledger.py" --receipts` (one row per plan step: `# · step · tier · model · override · outcome · esc · verify · calls · in · out · check`, plus the summary line with the agent-output share by model, e.g. `agent out by model: fable 40% · haiku 45% · sonnet 13%`). Paste it verbatim — the tokens are the SubagentStop hook's and the by-model shares are the tool's, never an estimate: quote that line, do not compute a split of your own — and add only the one-line comparison: "with `--routing off` every step would have run on the session model."
- Set `"active": false` in routing.json, then write `pending.json` in the state dir from the live context: `{"skill":"run-plan","task":"<name>","mode":"<dial>","started_at":"<routing.started_at>","self_check":"<passed>/<units>","notes":"<escalations>"}` for the ledger. The Stop hook writes the ledger line and archives routing.json under `runs/` — `/smartuse:receipts <task>` shows it later.

## Rules
- Foreground only. Never the Workflow tool from this skill — multi-agent runs need the user to type the request themselves ("use a workflow"); offer that in one line when ≥ 3 units are independent.
- The session model tiers; a brief restates the rules because agents do not inherit them; agents never ask the user.
- One escalation, one re-verify, then stop and report. No silent retries, no second batch without "go".
- Nothing outside the unit's files; no commits (the user's commit procedure does that, and `living-docs` runs after it).
