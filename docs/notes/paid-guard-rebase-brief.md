# Brief: rebase the paid-guard branches onto 0.5.1 (2026-10-25, for the next session)

Read first: `docs/STATUS.md`, `docs/notes/paid-guard-plan.md` §7 (resume state), and `docs/notes/py-cache-fix-plan.md` §3 and §8 (what 0.5.1 changed in the guards). YK 2026-10-25: the rebases run in a fresh session, before any other 0.6.0 work.

## What
- `paid-guard` (3 commits: F1 `11ed477`, F2 `b14bd71`, hardening `d88444c`) and `paid-f3` (`83fcf6e`, WIP, untested; worktree `.claude/worktrees/f3`) start at `8caa819`, before 0.5.0. Both are unpushed: rebase, never merge.
- Their own files: `hooks/bash-guard.py`, `hooks/file-guard.py`, `hooks/tests/file-guard-test.sh`, `hooks/tests/run.sh` (these four overlap with 0.5.1) and `.github/workflows/ci.yml`, `hooks/tests/all.sh`, `hooks/tests/paid-cases.txt`, `hooks/tests/paid-guard-test.sh` (theirs alone). Plan §7's list of CHANGELOG / STATUS / README conflicts does not apply: the paid commits do not touch them.

## Steps (one command per shell call)
1. Baseline: on `paid-f3` (its worktree), run `paid-guard-test.sh` once and keep its last line: f3 is WIP, so a red suite after the rebase is only a rebase fault if it was green before.
2. `git -C ~/smartuse rebase main paid-guard`. Resolve each stop by the rule below, `git -C ~/smartuse add <file>`, `git -C ~/smartuse rebase --continue`. Then T1, one at a time: `run.sh`, `file-guard-test.sh`, `paid-guard-test.sh`.
3. `git -C ~/smartuse/.claude/worktrees/f3 rebase paid-guard`, the same resolution and the same three suites; compare `paid-guard-test.sh` with the baseline.

## Merge rule (replaces plan §7's, written before 0.5.1 restructured file-guard)
- `file-guard.py`: keep 0.5.1's structure whole (`win_part`, `odd_part`, `human_only`, `resolved`, the three readings, deny when a path cannot be resolved). `HUMAN_ONLY` = 0.5.1's alternation plus the paid branch's new files. Reason text: the paid branch's wording plus "or which Python runs the hooks". Docstring: 0.5.1's plus one clause per new file.
- `bash-guard.py`, the human-only rule: the union of the file alternations (0.5.1's interpreter alternative with its `[. ]*` and `(?![\w-]|\.\w)` kept as is), the paid branch's verb list, the reason text as above. The SQL rule keeps 0.5.1's `^` anchor. No new rule may rescan the text from every position: the 64 KB timing case in `run.sh` must still pass.
- Tests: keep both appended blocks in `file-guard-test.sh` and `run.sh`, 0.5.1's first; counts only grow (0.5.1: run 138, file-guard 26).
- Open default: if the paid verb list adds `rm`, an `rm` of the launcher cache is denied too, where 0.5.1 left it allowed (plan §3). **Default: accept** (the model never needs to delete it; the user can). Say so in the 0.6.0 CHANGELOG.
- A hunk that fits none of these: stop, show both sides, ask YK.

## Restate in every agent brief
- Only the files named; Edit tool, no whole-file pastes. One command per shell call, `git -C <dir> …`, no `cd`.
- Laptop suites one at a time (each Python start takes 0.4–3.6 s; low memory kills parallel runs). JSON fixtures with Windows paths go in a file, and an empty guard answer counts only once the input is proven to parse.
- Public repo: comments and commit messages describe the class of problem, never the steps to exploit it. No personal paths.
- Nothing is pushed until 0.6.0's own gates (plan `docs/notes/paid-guard-plan.md`).
