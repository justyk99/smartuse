# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 13:20 UTC)

Mandate (YK, 2026-10-22): the Brain drives to 1.0 and asks only for real decisions; the laptop session Smartuse-Worker does laptop-only steps. Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s`.

## Done
- **0.4.0 released:** on `main` at 5b3dbed (a merge of e4b678c, CI green on Linux, macOS, Windows, Python 3.9 and strict validate); a fresh `claude plugin install smartuse@smartuse` gets 0.4.0. Evals 8 of 8 (+0.88 over no plugin).
- Laptop re-test of the release's hooks (99eab34, Python 3.13): everything passes except 3 heartbeat timing checks (64 of 67) that overshoot as the slow run goes on; CI's Windows runner passes. The worker's report never reached the Brain (sent 12:39 to a name that does not route); found in its transcript at 13:08.
- Case studies 7 and 8 added to YK's training case studies (private repo, dev branch). Designs: `docs/notes/relay-design.md` (relay guards) and `docs/notes/one-session-design.md` (one session that delegates, the 0.5 main pattern).

## In progress
- Heartbeat test timing on slow interpreters (a worker; reproduce with a slow-start shim, measure around each call, keep the checks tight).

## Blocked on YK
- Release pages and tags for v0.3.0 and v0.4.0: one paste on the laptop (in the Brain's message of 2026-10-22 ~12:55 UTC).
- LinkedIn post #2: his one line + "post", Friday 23 Oct 13:00 MYT (wake-up armed).

## Next (mine)
- 0.5 in the design's order: `watch.py` → the wait gate + `STOPPED` status → the one-session steering (make-prompt, run-plan, README, two eval cases) → the paid-call guard.
- Every hand-off to the laptop session gets a watcher: a scheduled check-in that reads its transcript (messages from it do not arrive).
