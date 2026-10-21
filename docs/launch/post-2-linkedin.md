# LinkedIn post #2 — "a receipt per plan step" (smartuse 0.3.0)

*Status: numbers marked `{{…}}` are filled from the 2026-10-21 bench run; the table is pasted verbatim from `/smartuse:receipts`. Attach `docs/media/demo.gif`. Link: the v0.3.0 release page.*

---

Last week I posted a plugin that turns one line into a planner-grade kickoff. The question I got most: "fine, but when Claude runs the plan, what actually happened in each step, and what did it cost?"

Here is the answer. One receipt per plan step.

I typed one line into the bench repo: "add a CSV export of orders, with a test. Deadline next week, I sign off."

smartuse split it into {{N_STEPS}} steps, ran them without me saying "go" between them, and when it finished I typed `/smartuse:receipts`:

{{RECEIPTS_TABLE}}

What each column means, in plain words:
- tier / model: who did the step and why. Judgment stays with the session model. Build gets a fresh agent. Review gets a cheaper one.
- override: if I had retiered a step by hand, it would show here as "mechanical→build". The receipt never hides my hand.
- esc: the one allowed escalation. Twice-failed steps stop and ask, they do not loop.
- verify: what a fresh agent said about the delegated work. Not the builder grading itself.
- calls / in / out: the agent's real API calls and tokens, attached by a Stop hook that reads the agent transcript. Nothing estimated. When the hook cannot tell which step an agent belongs to, it leaves the receipt unattached rather than guess.

The run: {{COST}}, {{MINUTES}} min, {{TURNS}} turns. {{OUTCOME_LINE}}

Why I built it this way: every "token saving" number in this space is self-reported, and every router hides its decisions. A receipt per step is the smallest unit of evidence I could find. When I publish a routed-vs-not comparison, every row will have one of these behind it.

What it is not: a router. It is a dial (off / safe / aggressive) with receipts. It is not a measured saving yet. It is the thing that makes a measured saving checkable.

Open source, MIT, native Claude Code mechanisms only (skills, hooks, output styles). Install:

/plugin install smartuse --marketplace justyk99/smartuse

Release notes and the full receipts of this run are in the repo. Tell me which column you would add.

#ClaudeCode #AIAgents #DeveloperTools #BuildInPublic
