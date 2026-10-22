# One session that delegates — the main pattern (proposal, 2026-10-22). For the author.

Source: the incident "The 'step done' message that never arrived" (anonymised; the course's case study 8), in the same two-session setup as "The relay that turned photos into words" (case study 7, `relay-design.md`). A cloud **manager** session planned and reviewed; a laptop **builder** session coded and rendered; the owner pasted the manager's prompts into the builder and expected a ping when a step was done. The builder finished at 20:57 and sent "step done" with its own messaging tool; the message never arrived. The manager had stopped its git watcher earlier to save tokens and did not re-arm it after the hand-off. It learned the step was done from the owner, while the builder's push from a minute earlier sat on the remote the whole time.

The same day smartuse's own pair did the same: the laptop session's test report, sent at 12:39 UTC to a session name that does not route to a cloud session, never arrived; the planner found it by reading the laptop session's transcript at 13:08.

Status: **proposal, nothing built.** Each part below is the cheapest mechanism that enforces its rule, with the test that replays the incident. Build order at the end.

## The pattern
- **One orchestrator session runs where the files and tools live** (here: the laptop with the GPU renderer). The owner talks only to it, from the phone through Remote Control.
- **It keeps the judgment:** the plan, the reviews, the owner's taste.
- **It hands the mechanical work down, cheapest first:**
  1. **A command** (a render, a conversion, a test run) → a background task. Done = its exit code and its output files, checked in the session. No model tokens while it runs, and its completion wakes the session.
  2. **Model work without judgment** (bulk edits, tests written to a spec, a conversion that needs reading) → a subagent on a cheaper model with a full brief: the spec, the check, the files it may touch, every input as an absolute path ("open each one"), a turn budget. Then a verify step (the check, or a fresh agent).
  3. **Judgment** stays in the session.
- **Why this removes both incidents:** subagents and background tasks share the filesystem, so a photo is a path and never a description (case 7). Results return to the same session, so there is no "done" message to lose (case 8). One context instead of two means no relay text written twice and no hop to drop a file or a signal.
- This is already run-plan's loop: units, tiers, verify, a receipt per step, the until-done gate. The proposal makes it the front door and closes the gaps below.

## Trade-offs, said once
- The orchestrator lives on the laptop, so a sleeping or closed laptop is a stopped session (the same lesson). Keep it awake while it runs. A cloud session does not sleep, but it does not have the renderer either.
- One context grows. Keep the heavy reading in subagents, and run long renders as background tasks, never as an agent waiting on a process.
- Subagents cannot ask questions; unknowns come back as `unknown: … → who` and the orchestrator asks the owner.
- A second session is still right when the work needs another machine (a tool or OS that exists only there, a server). Then the three rules hold: "done" is a push, a file or an exit code, and a chat message is a courtesy; arm a watcher after every hand-off; and prefer one session wherever the machine allows.

## M1 — `watch.py`: the watcher as one command (rules 1 and 2)
- `bash "<plugin>/hooks/py.sh" "<plugin>/hooks/watch.py" --git <remote> <branch> [--path <file>] [--every 60] [--max 4h]` polls `git ls-remote` (no model tokens, one small request a minute) and exits 0 when the branch head moves (with `--path`, once that file exists at the new head), printing `pushed <sha> "<subject>" · <path>`. `--file <path>` waits for a local file; `--pid <n>` for a process. At `--max` it exits 3 with `no signal after 4h`, so the session is woken either way and never waits silently.
- The session runs it as a background task (Bash `run_in_background`); the task's completion notification is the wake-up.
- **Test that replays the incident:** a bare fixture remote; the watcher starts; the builder fixture pushes a commit adding `docs/M3-RESULT.md`, and a "step done" message goes nowhere. Expected: exit 0 within one poll, naming the commit and the file. In the incident nothing was polling. Also: no push → exit 3 at `--max`; a push without the file under `--path` → still waiting.

## M2 — the wait gate: "if nothing will wake you, you are stopped" (rule 2)
- **Mechanism:** a Stop hook beside until-done (0 tokens). It reads the session transcript and blocks the end of the turn once when a hand-off is open and no watcher is armed.
  - **Hand-off open** = since the last watcher was armed, one of: a message to another session (`SendMessage`, `mcp__claude-code-remote__send_message`); a push of a brief for another session (`docs/code-brief-*`, `docs/*-ANSWERS.md`); a final reply that hands work over or promises a later report (`paste this into …`, `I'll ping / tell / let you know`, `when … is done`). The last trigger is a pattern match: it catches the plain phrasing, not every phrasing.
  - **Watcher armed** = a background Bash task, `Monitor`, a scheduled check-in (`ScheduleWakeup`, `CronCreate`, `send_later`, `create_trigger`) or a PR subscription, not since stopped (`TaskStop` on its id) and not since finished. A task's end is in the transcript (checked on a 2.1.308 transcript): a `queue-operation` and a `user` record carrying `<task-notification>` with its `task-id`, the `tool-use-id` of the call that started it, and `<status>completed`.
  - **The block:** `you handed off (<what>, <when>) and nothing will wake you — the watcher started at <time> was stopped. Arm one: bash "<plugin>/hooks/py.sh" "<plugin>/hooks/watch.py" --git origin <branch> --path <result file> in the background, or schedule a check-in — or end with "STOPPED: nothing will wake me; <who> must."`. A reply that starts with `STOPPED:` passes, because honesty is the other way out. The second Stop always passes: one block, never a trap.
- **Test that replays the incident:** a fixture transcript of the manager. A background watcher is armed, then stopped with `TaskStop` ("to save tokens"). Then the builder's prompt is handed over (`paste this into the builder …`, or a pushed brief), then Stop. Expected: **blocked**, naming the stopped watcher and the hand-off. Today nothing blocks it, and that is the incident. Variants that pass: a watcher armed after the hand-off; a reply starting `STOPPED:`; no hand-off at all.
- **The builder-side twin** (rule 1, lower priority because this builder did push): a Stop after a "done" message to another session while the branch is ahead of its upstream is blocked once with `push first — the push is the done-signal; the message is a courtesy`.
- **Limits:** the reply trigger is a pattern match; a watcher on the wrong branch passes the gate (the block message names the result file to watch).

## M3 — the status line tells waiting from stopped (rule 2, for the owner)
- heartbeat shows `waiting on builder · watcher armed 20:41 (git origin/dev)` or `STOPPED · handed off 20:41, nothing will wake this session`, from the same state as M2.
- **Test:** a heartbeat fixture with a hand-off and no watcher → the line starts with `STOPPED`.

## M4 — steering into one session (rule 3): make-prompt and run-plan, no new skill
- **make-prompt:** the ground check answers "where do the files and tools live?": is the repo here, and do the tools the ask names resolve (`command -v <tool>`)? The kickoff gets a `Runs on:` line. The self-check line "right repo" becomes "right repo and machine (files and tools here)", so the list stays at 14. When the ask describes a relay ("I'll paste your prompts into my laptop session", "ping me when it's done"), the hand-off says: run this kickoff on <machine> as one session with run-plan; use a second session only for another machine, with its done-signal and a watcher.
- **run-plan:**
  - § 0 pre-flight: each unit's check command and tool must resolve here, and each input file must exist. A unit whose tool is elsewhere shows `needs-machine: <tool> not found here` in the dry-run table. A plan whose work is elsewhere stops with "run this plan on <machine>", not a relay from here.
  - A new `command` tier below `mechanical`: one command, no model, run as a background task; done = its exit code and output files.
  - Briefs carry every input as an absolute path.
- **README:** lead with the pattern in one line — "one session where your files and tools are: it keeps the judgment and hands the mechanical work to cheaper subagents, each with a brief and a check" — with the two-session rules under "When you need a second machine".
- **Tests that fail on this incident** (eval cases, model-graded):
  - `kickoff-two-sessions`: the prompt is the incident's setup ("plan the next step; I'll paste your prompt into my laptop session, which has the renderer; ping me when it's done"), in a repo where the renderer is not installed. Graders: a regex for `Runs on:`, plus a judge. To pass, the reply either moves the work to one session on the laptop with run-plan, or keeps two sessions with the push as the done-signal and a watcher armed. Either way it never promises a ping with nothing armed. The incident's reply ("paste this into the builder; I'll ping you when it's done") scores 0.
  - `run-plan-wrong-machine`: a task.md whose units render with a tool that is not on this machine → the dry run shows `needs-machine` and no unit starts.

## What this changes in the relay guards (case 7)
One session removes most of their reason. When photos are paths, there is no relay to guard (rules 1, 2 and 5), so those stay proposals for the second-machine case. The paid-call guard (rule 4) still matters: a cheap subagent can spend money as fast as a planner can.

## Build order (smallest first, then reach)
1. M1 `watch.py` and its tests. It is also what smartuse's own planner needs today for its laptop session.
2. M2 the wait gate and M3 the status line, with the replay tests above.
3. M4 the steering: make-prompt `Runs on:`, the run-plan pre-flight, the `command` tier and inputs by path, the README lead, and the two eval cases.
4. The paid-call guard (case 7, rule 4).
5. The relay guards (case 7, rules 1–2), for second-machine setups only.
