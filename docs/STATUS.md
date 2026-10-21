# STATUS — smartuse 0.3.0 relaunch (owner: Smartuse-Brain · updated 2026-10-21 15:20 UTC)

Gate: **23 Oct** — 0.3.0 released · demo gif · LinkedIn post #2 ("a receipt per plan step"). Branch: `claude/inspiring-galileo-8icw6s` (pushed; main untouched).

## Done
- **Receipt per plan step**: SubagentStop hook attaches the agent's real calls/tokens to the `running` unit in routing.json (two running → unattached, never guessed); run-plan records `override`, `escalated`, `verify`; Stop hook archives closed runs under `runs/`; new `/smartuse:receipts [task|all]` skill + eval case. Tests: ledger 13, bash-guard 44, until-done 23, file-guard 4 — all green; strict validate green (plugin + marketplace, both warnings fixed).
- CHANGELOG 0.3.0 final · `docs/releases/0.3.0.md` (release-page text) · README (table, roadmap, numbers) · SECURITY (4 hooks) · CI runs all 4 tests + term scan · versions 0.3.0 in both manifests · pyc files untracked.
- **Term scan** (`scripts/term-scan.py`, tree + history, generic patterns only — no private list present): 18 real hits in the tree, all fixed (company abbreviation, internal SQL/table names, employer version scheme, a real customer bug in a test log, `/home/yk` paths, author-suffixed fixtures). Remaining 50 tree hits are expected (guard's own deny patterns, placeholder names, public source URLs). History still carries the old names → fresh history (RELAUNCH.md §3) drops them.
- `docs/RELAUNCH.md`: the hand-run commands (pre-flight scan with your list → merge to main → fresh-history export → empty public repo → release → install check).

## In progress / Next
- Nothing on the branch; waiting on YK's hands (below). Optional before Thursday: one real `run-plan` on the bench repo to replace the self-reported receipts table in `bench/results-example/` with hook-attached numbers.

## Blocked
- (none)

## Decisions for YK
1. **Gate date**: 22 Oct is the Thursday, 23 Oct the Friday. I am working to 23 Oct.
2. **Public repo name**: RELAUNCH §3 recommends keeping `justyk99/smartuse` (rename current → `smartuse-archive`, private). Say if you want a new name — then two manifests + README change before the root commit.
3. **Incident, reported for transparency**: a doc-writing command of mine mis-terminated and ran RELAUNCH's shell lines inside this container: it checked out main (no commits were added, nothing new pushed — origin main and tags verified unchanged), and `git init` + commit ran in the container's home dir. That accidental repo had its remote removed and was moved into the session scratchpad; nothing left the container. The private-list file was not created.

## Needs YK's hands
- Paste `.smartuse-terms.local` on the laptop and run the scan (RELAUNCH §1). · Demo gif → `docs/media/demo.gif`. · Public repo (RELAUNCH §3–4). · Post #2.
