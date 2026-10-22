# A/B run 1 (2026-10-22, headless, 1 ask × 3 dials) — the run that found a run-plan defect

`bench/ab.sh --asks 1` on the bench repo with the 0.4.0-dev plugin. Ask: "add a CSV export of orders". One kickoff (`make-prompt quick`, 12/13, $1.55), then `run-plan --until-done` per dial on a fresh copy.

| dial | what happened | steps | npm test | cost | min |
|---|---|---|---|---|---|
| off | stopped before any step: NEEDS YOU on the CSV row shape, which the kickoff had already given as an `assumed:` default | 0 pass / 5 blocked | 2/2 (unchanged) | $0.34 | 0.8 |
| safe | same | 0 / 5 | 2/2 | $0.32 | 0.8 |
| aggressive | proceeded on the assumed shape: route + tests built, docs on haiku | 4 pass / 1 blocked (the commit) | 6/6 | $1.12 | 4.6 |

Not a routing result: the two stopped runs happened to be on Opus and the working one on another model, and the skill text let both readings through ("a unit that depends on an unanswered question is blocked"). Fix in the same commit: run-plan § 0 now says an open question with an `assumed:` default is answered for now (proceed, record in decisions.md, list under **Confirm**), and only a question with no default or a rule gate blocks. The receipts here are the hook archives of the three runs; `report.md` is `ab-report.py`'s output as it was (the cost deltas against a run that did no work are meaningless, which the report now flags).

What this run is good for: it is the first time the A/B harness caught a behaviour defect with evidence per dial, which is what it is for. The routed-vs-not numbers come from the re-run after the fix.
