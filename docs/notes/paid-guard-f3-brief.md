# 0.7.0 F3 brief — the port of the paid block (2026-11-13)

The spec is `paid-guard-plan.md` §8.4 F3, with §8.2 (V1–V10), §8.6 (constraints, method D) and §8.10 (F0 results). This file holds only the state F3 starts from.

## Start state
- Dev branch `paid-0.7.0`, local only: plan, F0 results, F1 (`1330bee`), F2 (`068f254`), each merged with `--no-ff`. T2 after the F2 merge: 11 of 11 ALL PASS.
- Track A worktree: `.claude/worktrees/pg7-a`, branch `pg7-a` at `068f254`. F3 builds there; the builder's first command is `git log -1`.
- Track B worktree: `.claude/worktrees/pg7-b` (F9, file tools); it can run beside F3.
- Source of the block: `paid-guard` `19c7e45`, checked out detached in `.claude/worktrees/pg7-ref`. Reference counts there: `paid-guard-test.sh` 328 PASS, `run.sh` 290 PASS, 0 FAIL each. The port must reach 328 or explain each missing case in the commit message.
- Counts on the dev branch now: `run.sh` 633 PASS; `fresh-gate-test.sh` 710 PASS; `until-done-test.sh` 50 PASS.
- Names now: `RULE_NAMES` = the 16 of 0.6.1 + `settings-file` (17). `FLOOR` = `human-only`, `trust-pin`, `config-switch`, `settings-file`. F3 appends `owner-file` to both and to `WAIVABLE`, and adds `GATE_NAMES = ("paid",)`. `heartbeat.py` `KNOWN_RULES` / `FLOOR_RULES` must follow in the same commit (heartbeat-test F5b compares them).
- F2's reader waiver (`_settings_waived`, `READERS`, `GIT_READERS`) is the mechanism `owner-file` reuses.
- F1 and F2 method D tools: `.claude/worktrees/pg7-scratch/f1/` and `f2/` (`replay.py`, `events.jsonl`, `rec/`).

## Open before F3 starts
- **D-YK12 (Monitor):** a Monitor call reaches PreToolUse as `Monitor`, and the guard's matcher is `Bash|PowerShell`. Yes → F3 also changes `hooks.json:6` to `Bash|PowerShell|Monitor`, `_main()` reads a Monitor command as Bash, plus cases. No → `hooks.json` stays identical; the gap goes to SECURITY.md in F10.
- E1, E2 (phone prompt records): needed by F5, not F3.

## Lessons from F1–F2 for the builder brief
- A timing text over 32 KB is tagged by `complexity()` and never reaches a waiver: keep each timing text under 32 KB.
- The installed guard checks the builder's own commands: fixtures that name a settings path, a paid host or a download pipeline go in a file, never on the command line.
- Testers: each suite is its own call, strictly one after another; ask for the PASS counts, not only the last line.
- Known flaky check: `ledger-test.sh:52` ("concurrent hooks"); one rerun, then report both runs.
