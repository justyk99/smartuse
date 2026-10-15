# X thread (8 tweets, each <= 260 chars)

1/
I typed one line into Claude Code: "PWA for the player site, a colleague builds push on top, 3-4 weeks". My own session turned it into a 60-line kickoff. Here is what it added, and why nobody writes that by hand.

2/
The kickoff had paths, owners, absolute dates, non-goals, gated deliverables, and open questions with named owners. Everything the one-liner lacked. A planner needs all of it. A human skips it every time because it is tedious.

3/
Half of that is already in the repo: reference code, owners from git log, lockfiles, missing tools, past tasks, incidents in memory. The other half is in your head. So make-prompt greps the first half and asks you about the second.

4/
The questions are basic and multiple choice. Option 1 is Claude's guess with the evidence beside it. "I don't know" is always allowed and comes back as an open question with an owner. Then it waits for your go.

5/
Three more pieces keep it honest. living-docs updates a DEV and a USER doc per feature after each commit, from the diff. reply-style gives you 7 voices with pros and cons. bash-guard denies risky commands, even in bypass mode.

6/
The part I care about most: receipts. A Stop hook sums token usage since a skill started and writes one ledger line. Numbers come from the transcript, not from me. Mine will appear as {{N_TASKS}} tasks, median {{MEDIAN_OUT_TOKENS}}.

7/
run-plan tiers each deliverable: judgment, build, mechanical, verify. It shows a dry-run routing table, runs foreground agents with a model per tier, verifies with a fresh agent, and writes a receipt per unit. Limits are listed in the README.

8/
gstack gives you roles. Ruflo gives you a swarm. yk-kit gives you a receipt.

/plugin marketplace add {{GITHUB_USER}}/yk-kit
/plugin install yk-kit@yk-kit
