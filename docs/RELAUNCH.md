# RELAUNCH — publishing smartuse 0.3.0 as a fresh-history public repo

Every command below is run **by YK, by hand, on the laptop**. The agent never force-pushes, never changes repo visibility, never pushes to `main` without green tests. Read each block before running it; run blocks one at a time, never paste the whole page into a shell (one block contains a heredoc).

## 0. Why fresh history
The current history (26 commits) carries the old plugin name, `/home/yk/...` paths and a few internal names in early design notes. The 0.3.0 branch cleans the tree; a fresh single root commit cleans the history. Nothing is lost: the CHANGELOG keeps the 0.1 → 0.3 story.

## 1. Pre-flight (10 min) — on the 0.3.0 branch, before anything public
```bash
cd ~/smartuse
git fetch origin && git checkout claude/inspiring-galileo-8icw6s && git pull --ff-only origin claude/inspiring-galileo-8icw6s
for t in run ledger-test until-done-test file-guard-test; do bash plugins/smartuse/hooks/tests/$t.sh | tail -1; done   # four × ALL PASS
claude plugin validate --strict plugins/smartuse && claude plugin validate --strict .                                   # two × Validation passed
```
Private-term scan with YOUR list. Create `.smartuse-terms.local` in the repo root with your editor (one term per line: employer, product codenames, colleague first names, internal hosts, DB names; a line starting with `re:` is a regex). The file is gitignored and the scan never prints a private term (hits show as `private#<line>` with the match masked):
```bash
git check-ignore -q .smartuse-terms.local && echo "ignored: ok"      # must print ok
python3 scripts/term-scan.py --history                               # exit 1 = hits; TREE hits must be 0 before step 3 (history hits vanish in step 3)
```
Expected generic hits that are fine: the credential-file names inside `bash-guard.py`, `hooks/tests/run.sh` and `security-profiles.md` (they are what the guard denies), the `usp_do_thing` / `t_x` / `_SESSIONS` placeholders in the design notes and skills, the public source URLs in `living-docs-design.md`. Anything else: fix in the tree, commit on the branch, re-run.

## 2. Merge to main (5 min) — only after step 1 is clean
```bash
git checkout main && git pull --ff-only origin main
git merge --no-ff claude/inspiring-galileo-8icw6s -m "smartuse 0.3.0: a receipt per plan step"
for t in run ledger-test until-done-test file-guard-test; do bash plugins/smartuse/hooks/tests/$t.sh | tail -1; done   # still ALL PASS on main
git push -u origin main
```
Wait for CI on GitHub (justyk99/smartuse → Actions): both jobs green. Red → fix on the branch, repeat.

## 3. Fresh-history public repo (15 min)
Decide the public name first. Option A (recommended): keep `justyk99/smartuse` as the public name — rename the current repo to `smartuse-archive` (keep it private) in GitHub → Settings → General → Rename, then create a new empty `smartuse`. Option B: a new name; then update `homepage` / `repository` in both manifests and the README install line before the root commit.

```bash
cd ~ && rm -rf ~/smartuse-public && mkdir ~/smartuse-public
git -C ~/smartuse archive --format=tar main | tar -x -C ~/smartuse-public     # tree only, no .git, from the merged main
cd ~/smartuse-public && ls -a | grep -c smartuse-terms                        # must print 0 (the private list never leaves the laptop)
python3 scripts/term-scan.py                                                  # tree only; expected hits only (see step 1)
git init -b main && git add -A && git commit -m "smartuse 0.3.0 — one line in, a planner-grade kickoff out, a receipt per plan step"
git tag -a v0.3.0 -m "smartuse 0.3.0"
git log --oneline | wc -l                                                     # must print 1
```
Create the empty public repo on GitHub (web UI: New repository → `smartuse` → Public → no README, no license, no .gitignore). Then, still in `~/smartuse-public`:
```bash
git remote add origin git@github.com:justyk99/smartuse.git
git push -u origin main          # a plain push to an EMPTY repo: no force needed. Refused = the repo is not empty — stop and look.
git push origin v0.3.0
```

## 4. Release + install check (10 min)
- GitHub → Releases → Draft new release → tag `v0.3.0` → title `smartuse 0.3.0 — a receipt per plan step` → paste `docs/releases/0.3.0.md` → Publish.
- From a shell that never had the plugin:
```bash
claude plugin marketplace add justyk99/smartuse && claude plugin install smartuse@smartuse && claude plugin list | grep smartuse   # 0.3.0 enabled
cd /tmp && claude -p "/smartuse:receipts" --max-turns 3                                                                          # "no run-plan run recorded" — no invented table
```
- Settings → Branches → protect `main` (require the `ci` checks). Settings → General → Issues on; Discussions optional.

## 5. The gif and the post (YK's hands)
- Record the gif on the laptop (≤ 60 s): one line → `make-prompt quick` → `run-plan --until-done` → `/smartuse:receipts` table. Save as `docs/media/demo.gif`, replace the README placeholder comment (line 14) with `![demo](docs/media/demo.gif)`, commit on `main`, push.
- LinkedIn post #2 "a receipt per plan step": the receipts table from the gif is the hook; link the release page, not the README. Draft lives in `docs/launch/post-2.md` once the gif exists.

## Rollback
Public repo wrong? Delete it (Settings → Danger zone) within the hour, fix, redo step 3. The archive repo and `~/smartuse` are untouched by steps 3–4.
