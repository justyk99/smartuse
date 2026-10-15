# Reddit post for r/ClaudeAI

**Title:** I built a plugin that turns a one-line ask into a planner-grade kickoff, and logs what each run cost

**Body:**

I maintain a legacy ASP.NET back office and a Vue 3 / .NET 8 rebuild. Most work starts as a thin ask like "PWA for the player site, a colleague builds push on top, 3-4 weeks".

My own Claude session once rebuilt that line into a 60-line kickoff: file paths, owners, absolute dates, non-goals, gated deliverables, open questions with owners. Nobody writes that by hand every time, so I packaged the habit as a plugin called yk-kit.

**What is in it**

- `make-prompt`: greps the repo for the half a planner can find (reference code, owners from git log, lockfiles, missing tools, past tasks, incidents in memory), then asks a few multiple-choice questions for the half in your head. Option 1 is Claude's evidence-backed guess. "I don't know" is always allowed. It waits for your go.
- `living-docs`: a DEV and a USER doc per feature, updated after each commit from the diff.
- `reply-style`: 7 reply voices with pros and cons, built on output styles.
- `bash-guard`: deny rules that fire even in bypass mode.
- `ledger` and `run-plan`: a Stop hook writes token usage per skill run; run-plan tiers deliverables, shows a dry-run routing table, and verifies with a fresh agent.

**Honest limits**

- Styles are instructions, not enforcement. Only the hook enforces anything.
- `make-prompt quick` costs real plan usage because the ground check reads a lot. It is for multi-day work, and it refuses one-file fixes.
- Subagents cannot ask questions, so unknowns come back as open questions with an owner.
- I have {{N_TASKS}} measured tasks so far. Treat the design as the claim, not a saving.

**Testers wanted.** Give it an ask from your own repo and tell me what the kickoff missed. Bug reports and "this question was pointless" are both useful.

```
/plugin marketplace add {{GITHUB_USER}}/yk-kit
/plugin install yk-kit@yk-kit
```
