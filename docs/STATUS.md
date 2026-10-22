# STATUS — smartuse 0.3.0 relaunch (owner: Smartuse-Brain · updated 2026-10-22 00:10 UTC)

Gate: **23 Oct** — 0.3.0 released · demo gif · LinkedIn post #2 ("a receipt per plan step"). Branch: `claude/inspiring-galileo-8icw6s` (pushed; main untouched).

## Done
- **Receipt per plan step** shipped and **verified on a real headless run** (2026-10-21, Claude Code 2.1.306): kickoff 14/14 ($1.57) → `run-plan --until-done` 6 steps, 6/6 tests, three reviews "no gaps", step 6 blocked by rule; the hook attached every agent's tokens to its step. $3.72, 6.4 min, 22 turns. Artefacts: `bench/results-example/2026-10-21-csv-export/`.
- **Demo gif** `docs/media/demo.gif` (22 s, 0.5 MB) rendered from that run's captured output by `scripts/render-demo.py` (nothing mocked); README embeds it. `demo-last-frame.png` = the receipts table for the post.
- **Post #2 draft** `docs/launch/post-2-linkedin.md`, numbers and table from the run.
- Tests 44/13/23/4 green · strict validate green · CHANGELOG, release notes `docs/releases/0.3.0.md`, README numbers, SECURITY, CI, versions 0.3.0.
- Term scan: 18 real tree hits fixed; remaining hits are expected generic patterns. `docs/RELAUNCH.md` has the hand-run commands.

## Next (mine, on YK's "merge")
- Merge the branch into `main` (tests green), push, tag `v0.3.0`, push the tag, watch CI. RELAUNCH.md §2.

## Blocked
- Nothing. **Fresh-history repo dropped**: `justyk99/smartuse` is already public, so a rewrite would un-publish nothing and would need a force-push. Development continues on the existing repo.

## Decisions for YK
1. Say **"merge"** and 0.3.0 goes to `main` + tag. Or review the branch first: `git diff main..claude/inspiring-galileo-8icw6s --stat`.
2. Private terms list: optional now (tree is clean on generic patterns); run it on the laptop per RELAUNCH §1 if you want.

## Needs YK's hands (after the merge)
- Click "Publish release" (text ready in `docs/releases/0.3.0.md`). · Paste the LinkedIn post + attach `demo.gif` / `demo-last-frame.png`. · Optional: a laptop screen recording to replace the rendered gif later.
