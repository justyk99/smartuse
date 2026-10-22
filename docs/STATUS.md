# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 06:10 UTC)

Gate: **23 Oct** — 0.3.0 released · demo gif · LinkedIn post #2. Dev branch: `claude/inspiring-galileo-8icw6s` (= main + 0.4.0-dev work).

## Done
- **0.3.0 is on `main`** (merge 7ef8e0e), CI green, `claude plugin update` from the marketplace verified 0.3.0-dev → 0.3.0. Demo gif + post draft on main. Hook tests 44/13/23/4 green; strict validate green.
- Verified the feature on a real headless run (receipts per step with hook-attached tokens): `bench/results-example/2026-10-21-csv-export/`.

- 0.4.0-dev on the branch: `bench/ab.sh` A/B runner (dry-run tested in CI; the real run waits on your spend decision) · receipts view with the agent-output share by model + `--json` (ledger-test 17/17) · design notes for receipts-per-step and the heartbeat.

- **Heartbeat shipped on the branch** (your "is it working or AFK?" weakness): `hooks/heartbeat.py` on every event → `status.json`; `/smartuse:status` → one line (`working · waiting on agent: general-purpose 4m12s · step 3/6 build·opus "tests"`, `waiting on you · 3m`, `NEEDS YOU: …`, `stalled? no activity 6m`); `/smartuse:status install` → terminal status line with model, context %, cost; plugin `subagentStatusLine` names the plan step per agent row. 54-case test; one live headless session verified every event lands; ~45 ms per event. Design: `docs/notes/heartbeat-design.md`.

## In progress
- Nothing running. Next candidates, your call: (1) cut **0.4.0 = heartbeat** now, A/B numbers later as 0.5; (2) run the A/B first (spend) and ship both as 0.4.0.

## Plan to go hands-free (YK asked for full automation)
- The cloud brain cannot create the release (harness blocks "public surface"; GitHub 403 on tag push) and cannot post on LinkedIn (no login). A **laptop session under Remote Control** can do both plus the heartbeat check: YK starts it once (6 typed lines, see the brain's message), messages the brain first (`@smartuse-46: line open`), then the brain drives it: checkout branch → hook tests → `gh release create v0.3.0` → `/smartuse:status install` → Friday 13:00 MYT post from the personal computer's browser after YK says "post".
- Post #2 rewritten to the ship-post rules (`docs/launch/post-2-linkedin.md`, 150 words, hook 43 chars, `[YK: …]` line pending). A scheduled wake-up at Fri 12:50 MYT runs the posting checklist.

## Decision for YK — A/B spend
Running the A/B for real costs plan usage: ≈ $5–6 per ask per dial on the bench repo, ≈ $50 and 1.5 h for 5 asks × 3 dials, run from here. Options: (a) run it here now, 5 asks × 3 dials, you get the table today; (b) you run `bench/ab.sh` on the laptop over the week against the bench repo or a real one (the "30 days of receipts" story); (c) both. Until you answer I build and dry-run-test the runner and spend nothing.
