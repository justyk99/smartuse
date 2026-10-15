cost $1.30 · turns 19 · 5.6 min

**NEEDS YOU: `npm run lint` can't pass yet. The repo has no ESLint config file, and ESLint 9 (the code-style checker) won't run without one. This was already broken before this task. Should I add a small `eslint.config.js`, or do you want lint dropped from the acceptance?**

**What**
- The new `GET /orders/export.csv` route works. It returns 200 and a `text/csv` file.
- The download has a header line, then one row per order.
- The acceptance is met except for the lint check above.

**How**
- `src/routes/orders.js`: added the export route, placed before `/:id`, plus a small CSV escaper. `computeTotal()` is unchanged.
- New `tests/orders-export.test.js`: covers a normal export, special characters, an empty store, and checks `/orders/1` still works. All 11 tests pass.
- I ran the end-to-end check from § 8:
```text
HTTP/1.1 200 OK
Content-Type: text/csv; charset=utf-8
Content-Disposition: attachment; filename="orders.csv"

id,userId,status,itemCount,total
1,1,paid,1,14.99
2,1,open,1,12.5
3,"yk, ""1""",open,1,3
```

**Receipts**
| unit | tier | model | outcome | escalated | agent tokens |
|---|---|---|---|---|---|
| 1 sign-off | judgment | session | pass | no | – |
| 2 decisions | judgment | session | pass | no | – |
| 3 route | build | opus | pass | no | 33.9k |
| 3–4 verify | verify | sonnet | no gaps | – | 29.6k |
| 4 tests | build | opus | pass | no | 31.1k |
| 5 end-to-end | judgment | session | pass | no | – |
| 6 close-out | mechanical | haiku | blocked: needs a commit | – | – |

- The automatic per-agent token logging wrote nothing to `receipts.jsonl`. The numbers above are the totals each agent reported.
- On `--routing safe` both build units ran on the session model. Only the review used a cheaper model (sonnet), about 31% of agent tokens.

**Look at first**
1. The lint question above.
2. The row shape is one row per order. That was the kickoff's default (§ 7 Q2), never explicitly confirmed. Please confirm it in `decisions.md`.
3. Nothing is committed. After your commit, the living-docs step and the move to `.task/COMPLETED/` (unit 6) can run.