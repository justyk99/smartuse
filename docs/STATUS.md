# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 12:15 UTC)

Mandate (YK, 2026-10-22): the Brain drives to 1.0 and asks only for real decisions; the laptop session Smartuse-Worker does laptop-only steps. Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s`.

## Done
- 0.3.0 on `main`, CI green; the marketplace serves it. The release page is still not published (see Blocked).
- 0.4.0-dev on the branch: heartbeat, receipts by model, A/B runner, Windows, audit batch one, state per repository, and now **state writes without a prompt** (skills write through `ledger.py --put/--unit/--run`; proven headless in default mode) and the bash-guard heredoc rule (eight bypasses closed): `run 126 · ledger 46 · until-done 36 · file-guard 10 · heartbeat 67 · ab 36`, strict validate passes.
- **A/B run 3** (5 bench asks × 3 dials, Opus pinned): median cost −24 % on both routed dials over 4 asks; agent output not lower; 11 of 12 runs green. In README with the caveats.
- Case study 7 ("the relay that turned photos into words") added to YK's training case studies (private repo, dev branch); the mechanism design is `docs/notes/relay-design.md`, listed in ROADMAP as proposed, outside the 1.0 bar.

## In progress
- CI on the merged state-writes commit (all legs).
- Next: score all 8 eval cases here (sandbox tools installed), one laptop re-test of the final head, then 0.4.0 to `main`.

## Blocked on YK
- The release page for v0.3.0 (and later 0.4.0): the harness will not let the Brain publish, and the laptop needs YK to allow `gh`. One paste in the laptop terminal ends this (my message of 2026-10-22 08:00 UTC).
- LinkedIn post #2: his one line + "post", Friday 23 Oct 13:00 MYT (wake-up armed).
- Whether the relay guards (rule 4, the paid-call guard, first) go into 1.0.

## Next (mine)
- CI green → eval scores → laptop re-test → 0.4.0 to `main`.
