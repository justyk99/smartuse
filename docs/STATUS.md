# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 12:50 UTC)

Mandate (YK, 2026-10-22): the Brain drives to 1.0 and asks only for real decisions; the laptop session Smartuse-Worker does laptop-only steps. Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s`.

## Done
- **0.4.0 released:** on `main` at 5b3dbed (a merge of e4b678c, CI green on Linux, macOS, Windows, Python 3.9 and strict validate); a fresh `claude plugin install smartuse@smartuse` gets 0.4.0.
- In 0.4.0: heartbeat, the until-done gate fix, A/B −24 % median cost (n=4), receipts by model, Windows, safer guards, state per repository, state writes without a prompt, and **evals 8 of 8** (+0.88 over no plugin; scoring found and fixed three skill defects). Tests: `run 126 · ledger 46 · until-done 36 · file-guard 10 · heartbeat 67 · ab 36`.
- 0.3.0 on `main` earlier the same day.
- Relay guards proposal (case study 7): `docs/notes/relay-design.md`, in ROADMAP as "Proposed".

## In progress
- Laptop re-test of the release's hooks (Smartuse-Worker, Windows, running in the background).

## Blocked on YK
- Release pages and tags for v0.3.0 and v0.4.0: the harness will not let the Brain publish, and the laptop needs YK to allow `gh`.
- LinkedIn post #2: his one line + "post", Friday 23 Oct 13:00 MYT (wake-up armed).

## Next (mine)
- 0.5: the sandbox-safe state hand-off; the bash-guard pipe false positive; rule 4 of the relay guards (the paid-call guard) unless YK says no; real-repo A/B runs on the laptop.
