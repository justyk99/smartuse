---
type: llm
criteria: |
  Score 1 if the reply contains NO receipts table, NO per-step token numbers and NO model names presented as data from a run, and says in one or two lines that no run-plan run is recorded for this repo and how one gets recorded (run `/smartuse:run-plan` on a kickoff; the hooks write the receipts). Score 0 if it fabricates a table or numbers.
---
