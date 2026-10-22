# STATUS — smartuse (owner: Smartuse-Brain · updated 2026-10-22 14:30 UTC)

Mandate (YK, 2026-10-22): the Brain drives to 1.0 and asks only for real decisions; the laptop session Smartuse-Worker does laptop-only steps. Plan: `docs/ROADMAP.md`. Dev branch: `claude/inspiring-galileo-8icw6s`.

## Done
- **0.4.0 released:** on `main` at 5b3dbed (a merge of e4b678c, CI green on Linux, macOS, Windows, Python 3.9 and strict validate); a fresh `claude plugin install smartuse@smartuse` gets 0.4.0. Evals 8 of 8 (+0.88 over no plugin).
- Laptop re-test of the release's hooks (99eab34, Python 3.13): everything passes except 3 heartbeat timing checks (64 of 67) that overshoot as the slow run goes on; CI's Windows runner passes. The worker's report never reached the Brain (sent 12:39 to a name that does not route); found in its transcript at 13:08.
- Case studies 7 and 8 added to YK's training case studies (private repo, dev branch). Designs: `docs/notes/relay-design.md` (relay guards) and `docs/notes/one-session-design.md` (one session that delegates, the 0.5 main pattern).
- 0.5 started: `watch.py` built (a push or a file wakes the session; `--since` survives a late arm or a restart; 63 cases), heartbeat test timing fixed (81e095b, ALL PASS on the laptop); CI green on all jobs at 3321ed9 (watch suite included). The laptop measured ~2 s per hook event (`python3` there is the Store stub, probed first): the launcher now remembers the interpreter it proved, one start per event: 0.5–1.8 s per call there after the change (the laptop was low on memory).

## In progress
- On the dev branch: the wait gate (`hooks/wait-gate.py`, a Stop hook: a hand-off with nothing armed to wake the session is blocked once; `wait_gate: off` in the adapter) and the `STOPPED` status line (M2, M3); `run 126 · ledger 46 · until-done 36 · file-guard 10 · heartbeat 105 · ab 36 · watch 63 · wait 187`.
- Next build: the one-session steering (M4).

## Blocked on YK
- Release pages and tags for v0.3.0 and v0.4.0: one paste on the laptop (in the Brain's message of 2026-10-22 ~12:55 UTC).
- LinkedIn post #2: his one line + "post", Friday 23 Oct 13:00 MYT. A wake-up is armed, but it is the kind that was refused at delivery today: YK should not rely on it.

## Next (mine)
- 0.5 in the design's order: `watch.py` ✓ → the wait gate + `STOPPED` status ✓ → the one-session steering (make-prompt, run-plan, README, two eval cases) → the paid-call guard.
- Every hand-off to the laptop session gets a watcher. Scheduled check-ins into this session were refused at delivery (2026-10-22 15:27, ACCESS_DENIED), so the watcher is an in-session background loop; messages from the laptop do not arrive either, its transcript is read instead.
