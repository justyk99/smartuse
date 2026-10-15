# Changelog

## 0.3.0 — in progress (2026-10-15)
- `run-plan --until-done`: the lazy-CEO loop. A Stop hook (`until-done.py`) refuses to end the turn while units or the repo's `check` command are unfinished; the model stops only for a real human question (`needs_human`), a double failure, a rule gate, or after 6 blocks. 10-case test.
- Adapter field `check:`.

## 0.2.0 — 2026-10-15, first public release
- Renamed from `yk-kit` to `smartuse` before the first push (no installs existed under the old name).
- Repository scaffolding: CI (hook + ledger tests, strict manifest validation), issue and PR templates, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, `docs/research` and `docs/notes`.
- living-docs is now model-invocable (`disable-model-invocation` removed) so the commit procedure can call it without the user typing anything; run-plan stays manual-only on purpose (it spends plan usage).
- Verified on real work (2026-10-15, Claude Code 2.1.300, Max plan): two `make-prompt quick` kickoffs on live repos — 0.9 min / 3.9k output tokens / 205k cache reads (a phase that turned out to be already built) and 1.8 min / 3.7k out / 195k cache reads (a parked design decision, 12/13 self-check); one `run-plan --units 1` on the second kickoff: tiered the unit mechanical → haiku agent (7 calls, 24k out), honestly marked it `blocked` by a read-only DB rule instead of working around it, receipt + visibility line written; the Stop hook wrote the ledger lines from the headless sessions by itself.
- Token counting: records that share one message id are partial views of one API call — keep the max of each counter per id (the first-record rule undercounted a 24k-token agent as 23). `ledger.py --recompute` rebuilds old lines.
- Plugin evals (2026-10-15, Claude Code 2.1.300, `--runs 1`): **4 of 4 cases pass with the kit (score 1.00 each); without the kit 0.00 / 0.00 / 0.50 / 0.00; mean gain +0.88; $1.27 list price per full run.** First runs found two real faults (a kickoff that was lost when the sandbox refused the save; living-docs not naming what was missing) — both fixed. `evals/results/2026-10-15-final/aggregate-result.json`.
- Plugin evals: need an OS sandbox for shell tools (`bubblewrap` + `socat` on Linux); graders must use JavaScript-safe regex (no `(?i)`), YAML single quotes for backslashes, and `allowed_tools` per case.
- ledger: Stop / SubagentStop hook writes `~/.claude/smartuse/ledger.jsonl` (per-task tokens by model, minutes, self-check) and per-agent receipts; `/smartuse:ledger` report; shared message ids counted once; self-contained test.
- run-plan: tier plan (judgment / build / mechanical / verify) with a dry-run table, foreground agents with a model per tier, one escalation, fresh-agent verification, receipts per unit, dial off / safe / aggressive.
- evals: 4 cases (kickoff-quick, reply-style-catalogue, bash-guard-sudo, living-docs-no-root) for `claude plugin eval`.

## 0.1.0 — unreleased (packaged 2026-10-15)
- make-prompt: interview (3 question banks: feature / bug / design), quick and dry modes, live context injection, 13-line self-check, 5-line human summary.
- living-docs: DEV.md + USER.md per feature with AUTO-MANAGED sections, updated from the commit diff; forked on a cheap model.
- reply-style: 7 output styles (lcd · bluf · engineer · teacher · minimal · plain · memo) with an identity → style table and pros/cons.
- bash-guard: 8 deny rules with a 32-case test; heredoc bodies treated as data.
- Verified 2026-10-15: `claude plugin validate` passes for plugin + marketplace; marketplace add → `plugin install smartuse@smartuse --scope local` → `plugin list` shows 0.1.0 enabled; `plugin details` inventory = 3 skills + 1 PreToolUse hook (harness-only, no model context cost); headless `--plugin-dir` run: `/smartuse:reply-style show` answered, bundled bash-guard denied `sudo` with the kit's wording; hook regression 32/32.
