# yk-kit

> One line in, planner-grade kickoff out. Then docs that stay current, a reply voice you choose, and a safety floor that fires even in bypass mode.

**Why this exists.** A planner needs paths, owners, absolute dates, non-goals, gated deliverables and open questions with owners. Nobody types that by hand every time. The repo already holds half of it; the other half is in your head. `make-prompt` greps the first half and asks you basic questions for the second. The result is a spec a fresh session can execute. The other three pieces keep the work honest afterwards.

gstack gives you roles. Ruflo gives you a swarm. yk-kit gives you a receipt. (Receipts land in 0.2 — see Roadmap.)

## Install (30 seconds)

```text
/plugin marketplace add <your-github-user>/yk-kit
/plugin install yk-kit@yk-kit
```
Then: `/yk-kit:make-prompt <one line about the work>`.

## What you get

| Skill | Type one line | You get |
|---|---|---|
| `make-prompt` | `/yk-kit:make-prompt add PWA install to the player site` | a ground check of your repo, ≤ 3 screens of multiple-choice questions (option 1 is Claude's evidence-backed guess, "I don't know" always allowed), an 8-section kickoff saved in your task folder, a 5-line summary for your team, a 13-line self-check. `quick` = no questions, every guess marked `assumed:`. |
| `living-docs` | runs after a commit lands | `DEV.md` (developers) + `USER.md` (operators) per feature, only the sections the diff touched, from the diff + task notes; forked on a cheaper model so your main window stays clean |
| `reply-style` | `/yk-kit:reply-style` | a table of 7 voices with who-they-are-for and pros/cons; picks one with two questions; installs it as a Claude Code output style |
| `run-plan` | `/yk-kit:run-plan <task.md> --routing safe` | a dry-run routing table (unit → judgment / build / mechanical / verify → model → why), then foreground agents with a model per tier, one escalation, a fresh-agent review of every delegated build, a receipt per unit, a one-line progress message per unit. `--routing off` = the baseline for your own A/B. |
| `ledger` | `/yk-kit:ledger` | every run's minutes, fresh vs cached input, output tokens and self-check, with medians — written by a Stop hook from the session transcript, 0 model tokens |
| `bash-guard` | always on | denies pipe-to-shell, `sudo`, recursive deletes of a tree, world-writable chmod, credential-file reads, destructive SQL through shell tools, force-push, svn revert — with the safe alternative in the reason. 32 regression cases. |

## Honest limits
- Styles and skills are instructions, not enforcement; the hook is enforcement.
- `make-prompt quick` costs real plan usage because the ground check reads a lot: in the author's runs, 1–8 minutes and 3–4k output tokens on top of 130–200k cached reads per kickoff ($0.5–3 at API list prices). Right for multi-day work, wrong for one-file fixes — which it refuses. `/yk-kit:ledger` shows your own numbers.
- Subagents cannot ask you questions. Unknowns come back as `unknown: … → who`.
- Numbers in this README come from the author's own runs on two production codebases; the reproducible benchmark ships with 0.2.

## Configure per repo (optional)
`.claude/yk-kit.local.md` with YAML frontmatter: `vcs`, `task_root`, `archive_root`, `docs_root`, `task_template`, `svn_flags`, `author`, `jira_cli`. Without it the skills detect git/svn and the usual folders.

## Roadmap
- 0.1 (now): the four pieces above.
- 0.2 (in progress, most of it in this repo already): `run-plan` + receipts + `ledger`; `bench/` = a sample repo + 5 scripted asks anyone can re-run (`bench/run.sh`); `evals/` = 4 `claude plugin eval` cases (need `bubblewrap` + `socat` on Linux for the sandbox).
- Then: "30 days of receipts" — the measured post.

## Where it came from
Built inside a legacy ASP.NET back office and a Vue 3 / .NET 8 rebuild, by one developer, with every rule born from a dated incident. Research notes for each piece are in `plugins/yk-kit/docs/`.

MIT.
