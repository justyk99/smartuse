---
name: run-plan
description: Execute a saved kickoff (the task.md that make-prompt wrote) with a tier plan and receipts. The session model tags each deliverable judgment / build / mechanical / verify, shows a routing table as a DRY RUN (unit → tier → model → why → turn budget) and waits for "go"; then runs units in the FOREGROUND through the Agent tool with the model per tier (never above the session's model), writes a receipt per unit, verifies every delegated result with a fresh agent, and closes with a receipts summary. Dial: --routing off | safe (default) | aggressive. `--until-done` = the lazy-CEO loop: no "go" between batches, the Stop gate refuses to end the turn while units or the repo check are unfinished, stops only for a real human question, a double failure, a rule gate or the cap. Use when the user says "run the plan", "execute the kickoff", "start deliverable 1", or answers make-prompt's hand-off with "go".
argument-hint: "<task folder or task.md> [--routing off|safe|aggressive] [--units N] [--yes] [--until-done]"
allowed-tools: Read, Grep, Glob, Agent, Write, Edit, Bash(ls *), Bash(cat *), Bash(date *), Bash(mkdir *), Bash(git diff *), Bash(git status *), Bash(svn diff *), Bash(svn status *)
disable-model-invocation: true
---

# run-plan — tiered execution with receipts (v0.1, 2026-10-15)

Why: the kickoff names the deliverables; this skill decides who does each one and proves what it cost. Receipts answer "what ran where, why, and did it pass" — the thing no router shows. The dial exists because lower models only pay off on small, checkable units.

Manual-only on purpose (`disable-model-invocation: true`): it spends plan usage, so only the user starts it with `/run-plan`. Skills that finish a kickoff should SUGGEST it, never call it.

## Live context
- Now: !`date -u +%FT%TZ || true` · session model: the model answering this turn (never spawn an agent on a stronger one)
- Arguments: `$ARGUMENTS` — a task folder or task.md; `--routing off|safe|aggressive` (default safe); `--units N` (default 3 per "go"); `--yes` skips the dry-run wait (headless only); `--until-done` = run every unit without waiting, keep going until done or a stop reason (see § 3b).
- Repo check command: from the adapter `check:` (e.g. `npm test`, `bash .claude/build-check.sh`) — required for `--until-done`; without it the gate only tracks unit status.

## 0. Read the kickoff
Read task.md: § 5 deliverables (the units), § 4 constraints and rabbit holes (restated in every brief), § 7 open questions (a unit that depends on an unanswered one is **blocked** — say so, do not guess), § 8 verification. No task.md → "run `make-prompt` first" and stop.

## 1. Tier each unit (the session model decides, never a hook or a keyword rule)
| Tier | What belongs here | Who runs it |
|---|---|---|
| **judgment** | design options, root cause, anything on money / security / shared procedures / other people's files, writing or changing the plan | the session model, in this conversation (no agent) |
| **build** | a well-specified change with a runnable check (test, build, script, screenshot compare) | `safe`: the session model via a fresh foreground agent · `aggressive`: one tier below the session model |
| **mechanical** | greps, caller inventories, file lists, doc updates, test-data generation, key or translation checks, formatting | the cheapest model your plan offers (`haiku` where available) via a foreground agent |
| **verify** | review a delegated unit's output against its spec, gaps only | a fresh agent, one tier below the session model (`sonnet` where available) |
`--routing off`: every unit on the session model, receipts still written — this is the A/B baseline. Rules: a unit without a runnable check is never `mechanical`; nothing is routed to a model stronger than the session's; a blocked unit stays blocked.

## 2. Dry run (always shown, then WAIT for "go" unless --yes)
Write `~/.claude/smartuse/projects/<repo folder name>/routing.json` (never inside the repo): `{"active":true,"task":"<name>","dial":"safe","started_at":"<now>","units":[{"id":1,"title":"…","tier":"mechanical","model":"haiku","why":"<one line>","budget_turns":15,"check":"<the runnable check>","blocked_by":null}]}` and print the same as a table: `# · unit · tier · model · why · budget · check`. Then: `Say "go" to run the first <N>, "go all", or "retier 3 build" to change a row.` Nothing runs before that.

## 3. Execute, one unit at a time, FOREGROUND
For each unit in order:
1. Spawn ONE Agent (foreground — the user sees the task card and tool count) with `model` per the table and a brief of ≤ 40 lines: the unit's spec and check · the constraints + rabbit holes from § 4 · the files it may touch (and only those) · "you cannot ask questions: write `unknown: <what> → <who>` instead" · "report: what you did, the check's output verbatim, files changed, unknowns" · the turn budget.
2. On return, append a receipt line to `~/.claude/smartuse/projects/<repo folder name>/receipts.jsonl`: `{"ts","unit":1,"title","tier","model","outcome":"pass|fail|blocked","check":"<first line of the check output>","escalated":false,"files":[…]}`. The SubagentStop hook adds the agent's tokens as its own line (same file) — do not estimate tokens yourself.
3. `fail`, or a blocking `unknown:` → **escalate once**: re-run the unit one tier up (never above the session model) with the failure pasted in; record `"escalated":true`. Still failing or blocked → stop the batch and go to § 4 Close anyway (the receipts and the ledger line must exist even for a blocked run); do not loop.
4. **Verify** every delegated `build` unit: a fresh agent (verify tier) gets the diff (`git diff` / `svn diff` of the unit's files) + the unit's spec: "list only gaps that affect correctness or the stated spec; no style". Gaps → fix on the build tier once → re-verify once. Judgment units are verified by the user, not by an agent.
5. After each unit print ONE line: `unit 2/5 done · mechanical/haiku · check passed · next: unit 3 (build)`. That line is the visibility rule — never run silently.
Stop after N units (default 3) and ask "go" again, so the user can read the receipts between batches.

## 3b. `--until-done` — the lazy-CEO loop
Write `"until_done": true` and a `"status": "pending"` on every unit into routing.json before the first unit. The check command is read by the gate from the human-written adapter (`check:` in `.claude/smartuse.local.md`) — you cannot set or change it from routing.json; if the adapter has none, the gate only tracks unit status. Then:
1. Run units in order with no "go" between batches. After each unit set its `status` (`pass` · `fail` · `blocked`) in routing.json and print the one-line progress message.
2. The `until-done` Stop hook refuses to end the turn while any unit is pending / running / failed or while the check command fails, and tells you what is left. Keep working; do not argue with the gate.
3. **Stop reasons — the only ways out:** (a) every unit is pass or blocked AND the check passes; (b) a unit needs the human: write the exact question into routing.json as `"needs_human": "<question>"` and make it the FIRST line of your final message (`NEEDS YOU: …`); (c) a unit failed twice (escalation used) → mark it `blocked`, record why, continue with units that do not depend on it; (d) a rule gate (a file owned by someone else, a shared server, money or security paths) → `needs_human`; (e) the gate has blocked 6 times → it lets you stop; say what is left.
4. Never commit. The final message: `NEEDS YOU` line if any, then the receipts table, then "what the human should look at first".
In an interactive session the user may also set `/goal <§ 8 acceptance>`; in headless use the CLI caps: `claude -p "/smartuse:run-plan <task.md> --until-done" --max-budget-usd N --max-turns M`.

## 4. Close (always — after a finished batch, a stop, or a block)
- Tick the units' boxes in task.md; add a dated line to `decisions.md` / `## Decisions` for every escalation or retier.
- Print the receipts table: `unit · tier · model · outcome · escalated · agent tokens in/out` (tokens from the SubagentStop lines) and the plain comparison: "delegated units used model X for N% of the agent tokens; with `--routing off` they would all have run on the session model."
- Write `~/.claude/smartuse/projects/<repo folder name>/pending.json` `{"skill":"run-plan","task":"<name>","mode":"<dial>","started_at":"<routing.started_at>","self_check":"<passed>/<units>","notes":"<escalations>"}` for the ledger; set `"active": false` in routing.json.

## Rules
- Foreground only. Never the Workflow tool from this skill — multi-agent runs need the user to type the request themselves ("use a workflow"); offer that in one line when ≥ 3 units are independent.
- The session model tiers; a brief restates the rules because agents do not inherit them; agents never ask the user.
- One escalation, one re-verify, then stop and report. No silent retries, no second batch without "go".
- Nothing outside the unit's files; no commits (the user's commit procedure does that, and `living-docs` runs after it).
