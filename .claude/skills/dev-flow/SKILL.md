---
name: dev-flow
description: Run a software project or feature start to end with quality first — brief, research, plan, contract, build, integrate, interactive test, review, ship, handoff — delegating each phase to the right model through the flow-* subagents, and telling the user exactly when to /clear. Use for "/dev-flow <ask>", "/dev-flow continue", or when the user starts a new project, a new feature or a new build phase.
---

# dev-flow (v1, 2026-10-24)

Priority: **quality and accuracy → speed → tokens.** The user keeps one setting in the menu (Opus, high). You switch models by delegating to the subagents below; never ask the user to change the model.

## Who does what
| Phase | Agent (model · effort) | You (the orchestrator) |
|---|---|---|
| 0 Brief · 1 Research · 2 Plan | `flow-planner` (strongest model on the account · xhigh, see the ladder); bulk reading by `flow-researcher` (Sonnet · medium) | collect the ask, show the plan, get the user's yes |
| 3 Contract | you (Opus · high) | interfaces, data shapes, fixtures, their tests |
| 4 Build | `flow-builder` (Sonnet · high), one per feature; own worktree and in parallel only in git repos (see version control) | brief each one: feature, contract, files in scope, test command |
| 5 Integrate | you | merge one feature at a time; full gate after each merge |
| 6 Use it | `flow-tester` (Sonnet · high) | fix nothing yourself without a failing scenario to point at |
| 7 Review | `flow-reviewer` (Opus · xhigh), fresh | majors go back to a builder; then 5 and 6 again |
| 8 Ship · 9 Handoff | you | docs, status, commit, push (or hand the diff over, see version control); the handoff below |

## Model ladder (planner)
The planner runs on the strongest model the account can use, so the same skill works for anyone who installs it.
1. Spawn `flow-planner` with the Agent tool's `model` set to the first rung: **`fable` → `opus`**. (Edit this one line when a stronger model ships.)
2. The spawn errors, or the planner's first line shows a weaker model than asked → re-spawn on the next rung and tell the user in one line ("planner on Opus: Fable isn't available on this account").
3. The planner's report starts with `Model: <the model id it runs on>`, so you can check rung 2.
4. Only the planner climbs the ladder. The reviewer stays on Opus · xhigh: when the planner ran on a different model, the review gets a second model's eyes.
5. A design or "which approach" question in the middle of a build goes to the planner the same way. The menu model never changes, not even for a new product direction: that is the planner's job too.

## Project rules beat this flow
Read the project's CLAUDE.md and rules before phase 0. Where they forbid something this flow does (commits, worktrees, a file type such as `.sql`, tests against a shared server, touching code someone else wrote), follow the project and say in one line which step changed. Put those limits in every builder's and tester's brief.

## Version control
Detect it before phase 4: a `.svn` folder or a working `svn info` → SVN; `git rev-parse` works → git; neither → no VCS.
- **git:** builders get the Agent tool's `isolation: "worktree"` and can run in parallel on independent features; you merge one at a time in phase 5.
- **SVN or no VCS:** no worktrees. Builders run one at a time in the same working copy, each told its exact files. Nobody commits: phase 8 shows the diff (`svn diff`) and the user commits. A stray `.git` inside an SVN working copy doesn't make it git: SVN wins.
- **Either:** the project says the user commits → same as SVN for phase 8.

## Your own past work first (every brief, research and plan)
- Read `my-work.md` next to this file: it says where the user's reuse map, lessons and decisions live on this machine. Pass those paths to `flow-planner` and `flow-researcher` in their brief.
- Before anything from outside, search the user's own work for the task's keywords: lessons (mistakes not to repeat), decisions (already made, don't re-decide), past projects and patterns (code shapes to copy), design systems (UI work).
- In the build-vs-reuse note, every candidate from the user's own work gets a verdict: **reuse as-is**, **adapt** (copy the structure, own code) or **avoid** (the lesson or reason). If `my-work.md` is missing or still a template, ask once where their past work lives.

## Rules that are never skipped
- Find the project's own files first: its status file, plan, decisions log, test gate (CLAUDE.md, README, `tests/`). Use them; never create a parallel set.
- No build without an approved plan. The plan names, for every feature: acceptance criteria as user actions, unit tests, one integration test, one interactive scenario, what must not change.
- Merge one feature at a time; run the full gate after every merge. Never claim done without the gate's own output line in the reply.
- Every feature gets the interactive pass (phase 6). Unit tests prove a part works; only the interactive pass proves the product works.
- Stop for the user only for: plan approval, anything irreversible, money, messages to other people, a decision with two reasonable answers. Everything else runs.
- For a batch that spans several turns, print once the line the user can paste to keep it running (you cannot start it yourself): `/goal <the batch's features>: <gate command> prints <pass line>, the interactive scenarios pass with screenshots saved, nothing outside <scope> changed, or stop after <N> turns`.

## When to tell the user to /clear
Say it at these moments, never in the middle of a feature:
1. The plan is approved (phase 2 done): planning talk fills the context and the build doesn't need it.
2. A batch of features is shipped (phase 8 done), or three features have gone through phase 7 in this session.
3. This session has been compacted once (you see a summary of earlier work at the top).
4. The user changes direction or starts another project.

First do the handoff: write back what this phase taught (a mistake → one dated line in the lessons file; a reusable piece → one row in the reuse map; a decision → the decisions file; paths in `my-work.md`), then rewrite the status file (≤ 25 lines: phase, done, next, locked decisions, must not change, open questions) and write the next brief. Commit them. Then print exactly:

```
▶ Phase <n> done: <one line>. Next: phase <n+1> <name>.
  Type /clear, then paste:  /dev-flow continue
```

## /dev-flow continue
1. Read the status file, the plan and the newest brief. Nothing else yet.
2. Answer the handoff test in five lines: what we are building and for whom · what is done · what is next · which decisions are locked · what must not change.
3. If any answer is missing or contradicts the files, fix the files with the user first. Otherwise continue with the next phase.

## Reporting
Each phase ends with one short block: what was done, the evidence (gate line, scenario results, screenshot paths), what is next, and the one thing that needs the user if any.
