# STATUS — smartuse 0.3.0 relaunch (owner: Smartuse-Brain · updated 2026-10-21 15:40 UTC)

Gate: **23 Oct** — 0.3.0 released · demo gif · LinkedIn post #2 ("a receipt per plan step"). Branch: `claude/inspiring-galileo-8icw6s` (pushed; main untouched).

## Done
- **Receipt per plan step** shipped and **verified on a real headless run** (2026-10-21, Claude Code 2.1.306): kickoff 14/14 ($1.57) → `run-plan --until-done` 6 steps, 6/6 tests, three reviews "no gaps", step 6 blocked by rule; the hook attached every agent's tokens to its step. $3.72, 6.4 min, 22 turns. Artefacts: `bench/results-example/2026-10-21-csv-export/`.
- **Demo gif** `docs/media/demo.gif` (22 s, 0.5 MB) rendered from that run's captured output by `scripts/render-demo.py` (nothing mocked); README embeds it. `demo-last-frame.png` = the receipts table for the post.
- **Post #2 draft** `docs/launch/post-2-linkedin.md`, numbers and table from the run.
- Tests 44/13/23/4 green · strict validate green · CHANGELOG, release notes `docs/releases/0.3.0.md`, README numbers, SECURITY, CI, versions 0.3.0.
- Term scan: 18 real tree hits fixed; remaining hits are expected generic patterns. `docs/RELAUNCH.md` has the hand-run commands.

## Next (mine, once YK answers)
- Public repo: create it, push the single-commit history + `v0.3.0` tag (no force, nothing to the existing main). Blocked on decision 1.
- Term scan with the private list (decision 2), then the final export.

## Blocked
- Public repo name (decision 1). Release page + LinkedIn posting have no tool here (YK, 5 min total).

## Decisions for YK
1. **Public repo name.** `justyk99/smartuse` exists (private, old history). Either (A) you rename it to `smartuse-archive` in Settings → General, then I create a new public `smartuse`; or (B) I create `smartuse-plugin` (or a name you give) and update both manifests + README. Say A or B.
2. **Private terms list.** Paste the terms here (they land only in the gitignored file and this session's transcript) or run the scan yourself per RELAUNCH §1. Or say "generic only" and I export as is.
3. Gate date: I am working to 23 Oct; 22 Oct is the Thursday.

## Needs YK's hands (after my export)
- Click "Publish release" (text ready in `docs/releases/0.3.0.md`). · Paste the LinkedIn post + attach `demo.gif` / `demo-last-frame.png`. · Optional: a laptop screen recording to replace the rendered gif later.
