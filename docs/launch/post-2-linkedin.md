# LinkedIn ship post, week 2 — Friday 23 Oct 2026, 13:00–15:00 MYT (v2, 23 Oct: smartuse 0.4.0 + the message that never arrived)

Written to YK's ship-post rules: 120–200 words, hook inside 49 characters, no link in the body, one real number, one thing that broke, YK's own line, two hashtags, no emojis. Not final until the `[YK: …]` line is replaced and YK says "post". Last-5-posts check: not done (no LinkedIn access from the brain session); glance at the activity page before posting. v2 replaces v1 (kept at the bottom): v1's "Next" (the three-way test) is done, and its first-comment link to the v0.3.0 release page is not live yet. Fresh-eyes review against the checklist: passed after splitting three dense blocks and dropping "cloud" / "status line".

---

## 1. The post

My AI promised to ping me. It never did.

This week two Claude assistants worked as a team on one job.
One plans online. One builds on my laptop.

The laptop one finished at 20:57 and sent "step done".
The message never arrived.

The planner had stopped watching to save money. I found out myself.

Released: smartuse 0.4.0, my free add-on for Claude Code.
One line on screen says working, waiting on you, or stalled. So I know if the AI is busy or asleep.

Measured: the same job, run three ways.
Handing the small steps to cheaper AI cut the typical cost per job by 24%.
Only 4 test jobs, so a direction, not a promise.

Building now: if an AI hands work to another one and nothing will wake it up, it has to say "stopped".
No more silent waiting.

[YK: one sentence in your own words — what annoyed you most this week]

What would you hand to a cheaper AI first?

#ClaudeCode #BuildInPublic

## 2. First comment (post right after)

Install in Claude Code: /plugin install smartuse --marketplace justyk99/smartuse
Code, the 24% test with its method and receipts, and the 0.4.0 notes: github.com/justyk99/smartuse
(If the v0.4.0 release page is up by then, link github.com/justyk99/smartuse/releases/tag/v0.4.0 instead.)

## 3. Visual

A screenshot of the README's "A/B, routed vs not" row (the −24 %, taken on your computer), or `docs/media/demo-last-frame.png` (the receipts table, one row per step) as the fallback.

## 4. Demo script (60 s, five beats)

1. Open: a terminal running Claude Code, the smartuse line at the bottom says "working". "One line tells me if it's working."
2. Input: `/smartuse:run-plan task.md --until-done` typed. "It splits the job and hands the small steps to cheaper AI."
3. Output: the A/B table, off $1.35 · safe $1.10. "Same jobs, 24 % cheaper. Four test jobs, so a direction."
4. The thing that broke: the builder's chat showing "step done" sent at 20:57, the planner's chat with nothing. "The message never arrived."
5. Next week: the line reading "STOPPED · handed off … nothing will wake this session". "Now it has to admit it."

Replace the [YK] line if present, then say "post".

---

## v1 (22 Oct, superseded)

## 1. The post

My own plugin blocked my own brain session.

This week I let a Claude session run the smartuse release by itself. Branch, tests, merge, demo gif. I signed off.

Shipped: one receipt per plan step. Claude splits a job into steps. After each step a small hook (a script that runs on its own) writes down which model did the work, whether a second agent checked it, and what it cost. Nothing guessed. The real run: 6 steps, 6 of 6 tests green, $3.72.

Built: a heartbeat. One line that says working, waiting on an agent, waiting on you, or stalled. Because from my phone I could not tell if the brain was busy or asleep.

Broke: the brain tried to read a web page in a way my guard treats as risky. My own guard said no. It does not know who is boss. Good.

[YK: one sentence in your own words — what annoyed you most this week]

Next: the same job under three routing settings, side by side, to see if the cheap models save anything at all.

What's the first task you'd throw at it?

#ClaudeCode #BuildInPublic

## 2. First comment (post right after)

Install in Claude Code: /plugin install smartuse --marketplace justyk99/smartuse
Code, receipts of the run, and the release notes: github.com/justyk99/smartuse/releases/tag/v0.3.0

## 3. Visual

`docs/media/demo-last-frame.png`: the terminal with the receipts table, one row per step, the tokens column filled by the hook. (Or `docs/media/demo.gif`, 22 s: one line typed, the plan runs, the table appears.)

## 4. Demo script (60 s, five beats)

1. Open: a terminal, `claude`, the smartuse prompt. "One line in."
2. Input: the ask typed, `make-prompt quick`. "It writes the plan. 14 of 14 checks."
3. Output: `run-plan --until-done` finishes, `/smartuse:receipts` shows the table. "Six steps. Each with its model, its check, its cost."
4. The thing that broke: the bash-guard denial line on screen. "My own guard blocked my own brain. Kept it."
5. Next week: `/smartuse:status` line in the status bar. "Working, waiting, or stalled. I'll know."
