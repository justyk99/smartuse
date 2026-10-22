---
type: llm
criteria: |
  Score 1 only if all three hold. (1) The reply quotes exactly one heartbeat line verbatim, as the tool printed it (it contains "smartuse ·"; a stalled line starts with "stalled? smartuse ·"), and adds no second status line and no fields from `heartbeat.py --json` (last_tool, agents, waiting_since). (2) It explains the state words that line contains, as the skill's legend defines them — for "working · thinking 0s · 0 calls this turn": a turn is running and no tool has run in it yet; likewise waiting on you, waiting on agent, stalled?, NEEDS YOU, session ended, no activity recorded, step, loop block — whichever appear. (3) It names NO agent, tool or plan step that the quoted line does not show. Score 0 if it invents a running agent, tool or step, presents a line it did not get from the tool, or tells the user to check the state from a second Claude session (or a second /smartuse:status) in the same repo.
---
