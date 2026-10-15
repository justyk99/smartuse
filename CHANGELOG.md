# Changelog

## 0.2.0 — in progress (2026-10-15)
- ledger: Stop / SubagentStop hook writes `~/.claude/yk-kit/ledger.jsonl` (per-task tokens by model, minutes, self-check) and per-agent receipts; `/yk-kit:ledger` report; shared message ids counted once; self-contained test.
- run-plan: tier plan (judgment / build / mechanical / verify) with a dry-run table, foreground agents with a model per tier, one escalation, fresh-agent verification, receipts per unit, dial off / safe / aggressive.
- evals: 4 cases (kickoff-quick, reply-style-catalogue, bash-guard-sudo, living-docs-no-root) for `claude plugin eval`.

## 0.1.0 — unreleased (packaged 2026-10-15)
- make-prompt: interview (3 question banks: feature / bug / design), quick and dry modes, live context injection, 13-line self-check, 5-line human summary.
- living-docs: DEV.md + USER.md per feature with AUTO-MANAGED sections, updated from the commit diff; forked on a cheap model.
- reply-style: 7 output styles (lcd · bluf · engineer · teacher · minimal · plain · memo) with an identity → style table and pros/cons.
- bash-guard: 8 deny rules with a 32-case test; heredoc bodies treated as data.
- Verified 2026-10-15: `claude plugin validate` passes for plugin + marketplace; marketplace add → `plugin install yk-kit@yk-kit --scope local` → `plugin list` shows 0.1.0 enabled; `plugin details` inventory = 3 skills + 1 PreToolUse hook (harness-only, no model context cost); headless `--plugin-dir` run: `/yk-kit:reply-style show` answered, bundled bash-guard denied `sudo` with the kit's wording; hook regression 32/32.
