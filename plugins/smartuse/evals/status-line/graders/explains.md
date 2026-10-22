---
type: llm
criteria: |
  Score 1 if the reply quotes exactly one heartbeat line verbatim (it starts with "smartuse ·"), explains the state words it contains (working, thinking, waiting on you, waiting on agent, stalled, NEEDS YOU, no activity recorded — whichever appear), and names NO agent, tool or plan step that the quoted line does not show. Score 0 if it invents a running agent or step, or presents a line it did not get from the tool.
---
