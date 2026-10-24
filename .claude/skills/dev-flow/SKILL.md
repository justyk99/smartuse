---
name: dev-flow
description: Run a software project or feature start to end with quality first — brief, research, plan, contract, build, integrate, interactive test, review, ship, handoff — delegating each phase to the right model through the flow-* subagents, and telling the user exactly when to /clear. Use for "/dev-flow <ask>", "/dev-flow continue", or when the user starts a new project, a new feature or a new build phase.
---

# dev-flow (v0, 2026-10-24)

Priority: **quality and accuracy → speed → tokens.** The user keeps one setting in the menu (Opus, high). You switch models by delegating to the subagents below; never ask the user to change the model.

## Who does what
| Phase | Agent (model · effort) | You (the orchestrator) |
|---|---|---|
| 0 Brief · 1 Research · 2 Plan | `flow-planner` (Opus · xhigh); bulk reading by `flow-researcher` (Sonnet · medium) | collect the ask, show the plan, get the user's yes |
| 3 Contract | you (Opus · high) | interfaces, data shapes, fixtures, their tests |
| 4 Build | `flow-builder` (Sonnet · high, own worktree), one per feature, in parallel when independent | brief each one: feature, contract, files in scope, test command |
| 5 Integrate | you | merge one feature at a time; full gate after each merge |
| 6 Use it | `flow-tester` (Sonnet · high) | fix nothing yourself without a failing scenario to point at |
| 7 Review | `flow-reviewer` (Opus · xhigh), fresh | majors go back to a builder; then 5 and 6 again |
| 8 Ship · 9 Handoff | you | docs, status, commit, push; the handoff below |

Suggest Fable (never switch to it yourself) only for a brand-new product direction or a strategy call; say why in one line.

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

First do the handoff: rewrite the status file (≤ 25 lines: phase, done, next, locked decisions, must not change, open questions) and write the next brief. Commit them. Then print exactly:

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
