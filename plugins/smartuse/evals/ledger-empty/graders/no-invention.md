---
type: llm
criteria: |
  Score 1 if the reply contains NO ledger table and NO minute or token numbers presented as recorded data, says in one or two lines that the ledger is empty, and explains that a row is written by the Stop hook from pending.json when a skill run (make-prompt, run-plan or living-docs) finishes its hand-off. Score 0 if it fabricates a table, a row or numbers.
---
