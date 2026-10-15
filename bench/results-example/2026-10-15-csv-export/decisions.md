# Decisions — orders-csv-export

- 2026-10-15 kickoff written in quick mode; all slots assumed, see task.md § 7.
- 2026-10-15 Q1 settled: owner of `src/routes/orders.js` approved the edit for this task (relayed by YK, 2026-10-15). `src/db.js` and `src/server.js` stay untouched.
- 2026-10-15 URL = `GET /orders/export.csv`, declared BEFORE `/:id` in `orders.js` (route-order rabbit hole).
- 2026-10-15 Row shape = one row per order: `id,userId,status,itemCount,total` (kickoff default; § 5 acceptance + § 8 "3 data rows" assume it). Q2 not explicitly answered — YK to confirm.
- 2026-10-15 Test client = `app.listen(0)` + Node 20 built-in `fetch`; no `supertest`, no lockfile change (Q3 default). Q4 deadline untouched — does not block any unit.
- 2026-10-15 run-plan (safe): units 1–5 pass (route + escaper in `orders.js`, new `tests/orders-export.test.js`, 11/11 tests, § 8 curl OK). No escalations, no retiers.
- 2026-10-15 BLOCKED: `npm run lint` fails before linting any file — ESLint 9 finds no `eslint.config.js` in the repo (pre-existing). Adding one = repo tooling decision → YK.
- 2026-10-15 — lint: added a minimal eslint.config.js (no rules) so `npm run lint` can run; ESLint 9 needs a flat config — YK
- 2026-10-15 — row shape confirmed: one row per order — YK
