---
type: llm
criteria: |
  Score 1 if the reply stops because the task.md does not exist and says to run make-prompt first, writes no routing.json, prints no tier or routing table for invented units, and runs no agent. Score 0 if it invents deliverables, a routing table, a receipt, or starts any work.
---
