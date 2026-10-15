# One line in, planner-grade kickoff out

I maintain two things at once: a legacy ASP.NET back office, and the Vue 3 / .NET 8 rebuild that is slowly replacing it. Most of my days start with a thin ask. This is the one that changed how I work.

I typed this into Claude Code:

> PWA for the player site, a colleague builds push on top, 3-4 weeks

That is a normal ask. It is also nearly useless as a plan. Nobody can start from it without asking ten questions first.

My own Claude session turned it into a kickoff of about 60 lines. It listed everything the one-liner did not say:

- the paths of the files that already do something similar
- who owns each area, taken from the commit history
- absolute dates instead of "3-4 weeks"
- non-goals, so the PWA work does not quietly grow into the push work
- deliverables, each with a gate that says when it counts as done
- open questions, each with a named owner

I read it and thought: this is better than what I would have written. Then I thought: I would never have written it. Nobody writes that by hand every time. It is too tedious, so the plan stays in your head and the work starts blurry.

## Half the kickoff is in the repo, half is in your head

That is the idea behind `make-prompt`, the first skill in yk-kit.

A planner needs two kinds of input. The first kind a tool can find without asking you: reference code, owners from `git log`, lockfiles, tools that are missing on the machine, past task folders, incidents recorded in project memory. `make-prompt` greps for all of that before it says a word.

The second kind only you know: how long this is allowed to take, what you refuse to touch, who signs off. For that it asks a few basic multiple-choice questions. Option 1 is always Claude's best guess, with the evidence next to it. "I don't know" is always allowed, and it does not stall anything. An unknown comes back in the kickoff as an open question with an owner.

There is a `quick` mode with no questions at all. Every slot Claude had to guess is marked `assumed:` so you can see what to check. The skill ends by waiting for your "go". It does not start the work on its own.

It also refuses one-file fixes. If the ask fits in a sentence of diff, you do not need a kickoff.

## Three pieces that keep the work honest

The kickoff is the front door. Three other pieces cover what happens after.

**living-docs.** After each commit, it updates two documents per feature: a `DEV.md` for developers and a `USER.md` for operators. It reads the diff and the task notes, and rewrites only the sections the diff touched. It never records behaviour that is not in the committed code. It runs on a cheaper model in a forked context, so your main window stays clean.

**reply-style.** Seven reply voices, each shown with its pros and cons: `lcd`, `bluf`, `engineer`, `teacher`, `minimal`, `plain`, `memo`. You pick one with two questions. It is installed as a Claude Code output style. A style is an instruction, not enforcement, and the skill says so.

**bash-guard.** A set of deny rules that block the commands you never want run by accident: pipe-to-shell, `sudo`, recursive deletes, force-push, destructive SQL through shell tools. Each denial names the safe alternative. It is a hook, so it fires even in bypass mode. It ships with a regression test of {{BASH_GUARD_CASES}} cases.

## The receipts idea

Every orchestration project in this space makes a savings claim. In the comparison I read, the numbers were self-reported. I do not want to add another unverifiable number, so I tried to build the thing that is missing: a receipt.

A Stop hook sums the session transcript's token usage from the moment a skill was invoked and writes one line to a ledger: skill, mode, minutes, tokens by model, self-check score. `/yk-kit:ledger` prints the table and the medians. Computing it costs no model tokens.

On top of that sits `run-plan`, which executes a saved kickoff:

1. The session model tags each deliverable as judgment, build, mechanical or verify.
2. It shows a dry-run routing table: unit, tier, model, reason, turn budget. Nothing runs until you say "go".
3. Units run as foreground agents, with a model per tier. Never a model above the one you are already using.
4. A fresh agent verifies every delegated result.
5. Each unit gets a receipt, and a unit that fails escalates once.

There is a dial: `off`, `safe` (the default) or `aggressive`. Cheaper models only pay off on small units that can be checked, so the default stays careful.

## What I have measured so far

Not enough to publish a verdict. The reproducible benchmark is a sample repo and a set of scripted asks that anyone can re-run. Here is where the numbers will go once they are real:

- tasks measured: {{N_TASKS}}
- median output tokens per kickoff: {{MEDIAN_OUT_TOKENS}}
- eval cases passing: {{EVAL_PASS}}

Until those are filled in, treat every claim in this post as a description of the design, not a result.

## Limits, plainly

- Styles and skills are instructions. Only the hook enforces anything.
- `make-prompt` reads a lot of your repo. In quick mode that costs real plan usage. It is right for multi-day work and wrong for small fixes.
- Subagents cannot ask you questions, so anything unknown comes back as an open question with an owner.
- It was built inside two codebases of mine. Yours will differ, and I want to hear where it breaks.

If you try it, tell me which ask you gave it and what the kickoff missed.

## Install

```
/plugin marketplace add {{GITHUB_USER}}/yk-kit
/plugin install yk-kit@yk-kit
```
