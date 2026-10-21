# LinkedIn post #2 — "a receipt per plan step" (smartuse 0.3.0)

*Numbers and the table are from the 2026-10-21 bench run (`bench/results-example/2026-10-21-csv-export/`), the table verbatim from `/smartuse:receipts`. Attach `docs/media/demo.gif`. Link: the v0.3.0 release page. LinkedIn has no code formatting: paste the table as a screenshot of the gif's last frame (`docs/media/demo-last-frame.png`) and keep the text below it.*

---

Last week I posted a plugin that turns one line into a planner-grade kickoff. The question I got most: "fine, but when Claude runs the plan, what actually happened in each step, and what did it cost?"

Here is the answer. One receipt per plan step.

I typed one line into the bench repo: "add a CSV export of orders, with a test. Deadline next week, I sign off."

smartuse split it into 6 steps, ran them without me saying "go" between them, and when it finished I typed `/smartuse:receipts`:

```
| # | step | tier | model | override | outcome | esc | verify | calls | in | out | check |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Route decision confirmed (path, colu | judgment | fable |  | pass |  |  |  |  |  | decisions.md: decision line written 2026 |
| 2 | src/routes/orders-export.js: toCsv() | build | fable |  | pass |  | no gaps | 5 | 110.7k | 2.7k | npm run lint: clean (exit 0); sanity row |
| 3 | Mount export router in src/server.js | build | fable |  | pass |  | no gaps | 5 | 107.6k | 1.2k | curl export.csv: 200 text/csv, header +  |
| 4 | tests/orders-export.test.js (unit +  | build | fable |  | pass |  | no gaps | 3 | 64.6k | 1.6k | npm test: Tests 6 passed, 6 total (2 sui |
| 5 | Docs: DEV.md + USER.md + README line | mechanical | haiku |  | pass |  |  | 3 | 72.8k | 4.5k | grep 'orders/export.csv' README.md:5 hit |
| 6 | Commit by path, move task folder, /l | judgment | fable |  | blocked |  |  |  |  |  | blocked: run-plan never commits; user's  |
steps 5 pass · 1 blocked · 0 open · agent tokens in 355.8k / out 10.0k · delegated out 10.0k (100% of agent output) on claude-fable-5-1, claude-haiku-5-5, claude-sonnet-5-5
```

What each column means, in plain words:
- tier / model: who did the step and why. Judgment stays with the session model. Build gets a fresh agent. Review gets a cheaper one.
- override: if I had retiered a step by hand, it would show here as "mechanical→build". The receipt never hides my hand.
- esc: the one allowed escalation. Twice-failed steps stop and ask, they do not loop.
- verify: what a fresh agent said about the delegated work. Not the builder grading itself.
- calls / in / out: the agent's real API calls and tokens, attached by a Stop hook that reads the agent transcript. Nothing estimated. When the hook cannot tell which step an agent belongs to, it leaves the receipt unattached rather than guess.

The run: $3.72, 6.4 min, 22 turns (plus $1.57 and 2.4 min for the kickoff). Five of six steps passed, 6 of 6 tests green, lint clean, three reviews found no gaps. Step 6 is blocked on purpose: run-plan never commits. The commit is mine, and so is the sign-off it asked for.

Why I built it this way: every "token saving" number in this space is self-reported, and every router hides its decisions. A receipt per step is the smallest unit of evidence I could find. When I publish a routed-vs-not comparison, every row will have one of these behind it.

What it is not: a router. It is a dial (off / safe / aggressive) with receipts. It is not a measured saving yet. It is the thing that makes a measured saving checkable.

Open source, MIT, native Claude Code mechanisms only (skills, hooks, output styles). Install:

/plugin install smartuse --marketplace justyk99/smartuse

Release notes and the full receipts of this run are in the repo. Tell me which column you would add.

#ClaudeCode #AIAgents #DeveloperTools #BuildInPublic
