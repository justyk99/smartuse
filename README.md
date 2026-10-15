<p align="center"><strong>smartuse</strong></p>
<p align="center">Use Claude Code smartly: one line in, a planner-grade kickoff out — with a receipt for every run.</p>
<p align="center">
<a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
<img alt="Claude Code 2.1.300+" src="https://img.shields.io/badge/Claude%20Code-2.1.300%2B-black">
<img alt="plugin evals 4/4" src="https://img.shields.io/badge/plugin%20evals-4%2F4%20pass-brightgreen">
<a href=".github/workflows/ci.yml"><img alt="CI" src="https://github.com/justyk99/smartuse/actions/workflows/ci.yml/badge.svg"></a>
</p>

> gstack gives you roles. Ruflo gives you a swarm. **smartuse gives you a receipt.**

A planner needs paths, owners, absolute dates, non-goals, gated deliverables and open questions with owners. Nobody types that by hand every time. Half of it is in your repo; the other half is in your head. `make-prompt` greps the first half and asks you a few multiple-choice questions for the second. The result is a spec a fresh session can execute. The other pieces keep the work honest afterwards: docs that update themselves after each commit, a reply voice you choose, a safety floor that fires even in bypass mode, and a ledger that shows what every run cost.

<!-- demo: docs/media/demo.gif — one line in, kickoff out, the receipts table (60 s). Recording pending. -->

## Install (30 seconds)

```text
/plugin install smartuse --marketplace justyk99/smartuse
```
Or from your shell: `claude plugin marketplace add justyk99/smartuse && claude plugin install smartuse@smartuse`. Then type `/smartuse:make-prompt <one line about the work>`.

## What you get

| Skill | You type | You get |
|---|---|---|
| `make-prompt` | `/smartuse:make-prompt add PWA install to the player site` | a ground check of your repo (reference code, owners from git log, lockfiles, missing tools, past tasks, incidents in memory), ≤ 3 screens of multiple-choice questions where option 1 is Claude's evidence-backed guess and "I don't know" is always allowed, an 8-section kickoff saved in your task folder, a 5-line summary for your team, a 13-line self-check. `quick` = no questions, every guess marked `assumed:`. |
| `run-plan` | `/smartuse:run-plan <task.md> --routing safe` (add `--until-done` for the loop) | a dry-run routing table (unit → judgment / build / mechanical / verify → model → why), then foreground agents with a model per tier, one escalation, a fresh-agent review of every delegated build, a receipt per unit, one progress line per unit. `--routing off` is the baseline for your own A/B. `--until-done` keeps going without "go": a Stop gate refuses to end the turn while units or the repo check are unfinished; it stops only for a real human question, a double failure, a rule gate or the cap. |
| `living-docs` | runs by itself after a commit lands | `DEV.md` (developers) + `USER.md` (operators) per feature, only the sections the diff touched, from the diff + task notes; forked on a cheaper model |
| `reply-style` | `/smartuse:reply-style` | 7 voices (lcd · bluf · engineer · teacher · minimal · plain · memo) with who-they-are-for and pros/cons, installed as a Claude Code output style |
| `ledger` | `/smartuse:ledger` | every run's minutes, fresh vs cached input, output tokens and self-check, with medians. Written by a Stop hook from the session transcript; costs 0 model tokens |
| `bash-guard` | always on | denies pipe-to-shell, `sudo`, recursive deletes of a tree, world-writable chmod, credential-file reads, destructive SQL through shell tools, force-push, svn revert — and names the safe alternative. 32 regression cases |

## How it works

```mermaid
flowchart LR
  A[one line] --> B[ground check<br/>repo · git log · memory · past tasks]
  B --> C[≤ 3 question screens<br/>option 1 = best guess]
  C --> D[kickoff.md<br/>8 sections · self-check]
  D --> E[run-plan<br/>tier · dry run · go]
  E --> F[agents per tier<br/>verify · escalate once]
  F --> G[receipts.jsonl + ledger.jsonl]
  D --> H[commit] --> I[living-docs<br/>DEV.md · USER.md]
```

## Measured (2026-10-15, Claude Code 2.1.300, Max plan)

| What | Result |
|---|---|
| `claude plugin eval`, 4 cases, with vs without the plugin | **4 of 4 pass with it** (1.00 each); without: 0.00 / 0.00 / 0.50 / 0.00 · mean gain **+0.88** · $1.27 list price per full run |
| `make-prompt quick` on three real asks (two production repos + the bench repo) | 0.9 – 1.8 min · 3.1k – 3.9k output tokens · 130k – 205k cached reads each · self-check 11/13 – 12/13 |
| `run-plan` first real unit | tiered to Haiku (7 calls, 24k output tokens), reported **blocked** by a read-only database rule instead of working around it |
| `run-plan --until-done`, bench repo, one line in | kickoff 14/14 → endpoint + 4 tests built (11/11 pass) → verified end to end → stopped with a precise human question (pre-existing lint gap). $1.30, 5.6 min, 19 turns. `bench/results-example/` |
| bash-guard · ledger hook | 32 / 32 and 5 / 5 regression cases |

Re-run them yourself: `claude plugin eval plugins/smartuse --runs 1 --allow-tools "Bash,Read,Grep,Glob,Agent,Write,Skill"` (Linux needs `bubblewrap` + `socat` for the sandbox) and `bench/run.sh` (a sample repo with a planted rounding bug + 5 asks).

## Honest limits
- Skills and styles are instructions. The hook is the only enforcement.
- `make-prompt quick` reads a lot: budget 1–8 minutes and real plan usage per kickoff. It refuses one-file fixes.
- Subagents cannot ask you questions. Unknowns come back as `unknown: … → who`.
- Token savings from `run-plan` routing are **not yet measured**; the A/B on 20 real tasks is on the roadmap. The ledger exists so that the number, when published, has a line of evidence per task.

## Configure per repo (optional)
`.claude/smartuse.local.md` with YAML frontmatter: `vcs`, `task_root`, `archive_root`, `docs_root`, `task_template`, `svn_flags`, `author`, `jira_cli`, `check` (the runnable check `run-plan --until-done` must pass, e.g. `npm test`). Without it the skills detect git/svn and the usual folders. Receipts live under `~/.claude/smartuse/`, never inside your repo.

## Repository map
```
plugins/smartuse/      the plugin: skills/ · output-styles/ · hooks/ (bash-guard, ledger, tests/) · evals/ · docs/
bench/                 reproducible mini-benchmark: sample repo + 5 asks + runner
docs/research/         the reading behind the design (reply styles, security profiles, the routing landscape)
docs/notes/            design notes with test logs (make-prompt, living-docs)
```

## Roadmap
- **0.2** (this release): make-prompt · run-plan · living-docs · reply-style · ledger · bash-guard · evals · bench.
- **0.3**: the 20-task routed-vs-not A/B with the ledger as evidence; routing receipts with a user-override field; a `/smartuse:receipts` view per task.
- Then: "30 days of receipts", the measured post.

## Contributing
Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Every change to a hook needs its test (`plugins/smartuse/hooks/tests/`). Security reports: [SECURITY.md](SECURITY.md).

## Credits and prior art
Built on Claude Code's official mechanisms only (skills, hooks, output styles, plugin evals). Ideas acknowledged: Anthropic's "let Claude interview you" pattern, the Living Docs template (Diew), superpowers `brainstorming` (obra), NawkaRouter / claude-router / gearbox for the routing-ladder shape, gstack for proving that a story and a 30-second install matter, Shape Up for appetite · rabbit holes · no-gos. Details and sources in `docs/research/`.

## Author
JustYK — a full-stack developer who grew this inside a legacy ASP.NET back office and a Vue 3 / .NET 8 rebuild, one incident at a time. MIT.
