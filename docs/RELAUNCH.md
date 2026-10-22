# RELAUNCH — releasing smartuse 0.3.0 on the existing public repo

`justyk99/smartuse` is already public, so there is no fresh-history repo and no rename. Development continues on it. The old history carries a few internal names in early design notes; they were already public, a rewrite would not un-publish them, and a force-push is against the rules. The tree is clean from 0.3.0 on (`scripts/term-scan.py`).

Roles: the agent merges and tags only with tests green and on YK's explicit "merge"; it never force-pushes and never changes visibility. YK clicks the release button and posts.

## 1. Pre-flight (agent, done on 2026-10-21)
- Hook tests 44 / 13 / 23 / 4 green · `claude plugin validate --strict` green on plugin and marketplace.
- Term scan on the tree: no private terms; remaining hits are the guard's own deny patterns, placeholders and public URLs.
- Optional, on the laptop: write `.smartuse-terms.local` (gitignored, one term per line, `re:` prefix for a regex) and run `python3 scripts/term-scan.py` — the file never leaves the laptop and no term is printed.

## 2. Merge and tag (agent, on "merge")
```bash
git checkout main && git pull --ff-only origin main
git merge --no-ff claude/inspiring-galileo-8icw6s -m "smartuse 0.3.0: a receipt per plan step"
for t in run ledger-test until-done-test file-guard-test; do bash plugins/smartuse/hooks/tests/$t.sh | tail -1; done   # four × ALL PASS
git push origin main
git tag -a v0.3.0 -m "smartuse 0.3.0 — a receipt per plan step" && git push origin v0.3.0
```
Then CI (`justyk99/smartuse` → Actions) must be green on `main`.

## 3. Release page (YK, 2 min)
GitHub → Releases → Draft new release → choose tag `v0.3.0` → title `smartuse 0.3.0 — a receipt per plan step` → paste `docs/releases/0.3.0.md` → Publish.

## 4. Install check (either of us, 2 min)
```bash
claude plugin marketplace add justyk99/smartuse && claude plugin install smartuse@smartuse && claude plugin list | grep smartuse   # 0.3.0 enabled
cd /tmp && claude -p "/smartuse:receipts" --max-turns 3                                                                          # "no run-plan run recorded" — no invented table
```

## 5. The post (YK, 5 min)
`docs/launch/post-2-linkedin.md` is the text. Attach `docs/media/demo.gif`; LinkedIn strips code formatting, so put the receipts table in as the image `docs/media/demo-last-frame.png`. Link the release page.

## Later
- Settings → Branches → protect `main` (require the `ci` checks).
- A laptop screen recording can replace the rendered gif any time; drop it at `docs/media/demo.gif`.
