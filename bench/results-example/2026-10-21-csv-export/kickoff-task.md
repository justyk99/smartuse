# CSV export of orders — kickoff (2026-10-21, written by /make-prompt, mode: quick)

Every slot below is `assumed:` unless tagged `verified:`. Correct by exception.

## 1. Where things are (verified 2026-10-21)
- Work repo: this one (`shop-orders-api`), branch `main`, one commit `0419e08 fixture`. Gates from CLAUDE.md: never touch `src/db.js`; `src/routes/orders.js` is owned by another developer, tell the user before editing it; task folder in `.task/ACTIVE/`, docs in `docs/features/`.
- Target code: `src/server.js` (14 lines, mounts routers, exports `app`) · `src/routes/orders.js` (25 lines, exports `{ router, computeTotal }`) · `src/db.js` (13 lines, `db.orders` array, read only) · `tests/orders.test.js` (9 lines, unit tests only, no HTTP tests yet).
- Reference code: `src/routes/users.js` (13 lines) is the plain-router pattern to copy for a new router file.
- Existing work: none. `grep -ri csv` over the repo is empty; `.task/ACTIVE`, `.task/COMPLETED`, `docs/features` hold only `.gitkeep`; no project memory dir; no `.claude/rules`.
- Attachments read: none given.

## 2. People, scope split, dates, appetite
- Asked by: the user (VCS name `sample-dev` per `.claude/smartuse.local.md`). Sign-off: the user (stated in the ask).
- Working alongside: the owner of `src/routes/orders.js` — name `unknown → user`. The plan avoids editing that file so no sanction is needed.
- The user owns: endpoint, test, docs. Not the user: nothing identified.
- Dates: target `assumed: 2026-10-28` ("next week" = today + 7). Hard date `unknown → user`. Review with the user on `assumed: 2026-10-27`.
- Appetite: `assumed: one day of work`. If it runs over, cut the `Content-Disposition` download header and the live-server smoke test; keep the endpoint and the test.

## 3. Non-goals (do not build, do not touch)
- No filtering, pagination, date ranges, or query parameters on the export.
- No fix to the rounding TODO in `computeTotal` (invoice service disagreement). The CSV reuses `computeTotal` as is, so totals match `GET /orders` exactly.
- No content negotiation on `GET /orders` (Accept: text/csv). That means editing `orders.js`.
- No one-row-per-line-item layout. One row per order.
- No changes to `src/db.js` (CLAUDE.md), no new runtime dependencies, no new dev dependencies (see § 4).
- Files of others: `src/routes/orders.js → unknown owner (user to name)`. Do not edit.

## 4. Facts that constrain the design + rabbit holes
- Stack: Node 20 per CLAUDE.md, Node 22.22.0 on this PC, Express 4.19, Jest 29, ESLint 9 with zero rules (lint = syntax check only) — verified: `package.json`, `eslint.config.js`, `node -v`.
- `npm test` passes today (2 tests) — verified: run on 2026-10-21.
- `package-lock.json` and `node_modules/` are untracked and there is no `.gitignore` — verified: `git status`. Gate: stage files by path, never `git add -A`.
- `computeTotal` is already exported from `orders.js`, so a new router can import it without editing that file — verified: `src/routes/orders.js:25`.
- Money is floats; `4.995 × 3` in fixture order 1 is a rounding edge — verified: `src/db.js:4`, `docs/ARCHITECTURE.md`. Gate: the CSV total must equal the JSON `total` for the same order, not a recomputation.
- No `supertest` installed — verified: `ls node_modules/.bin`. Decision (assumed): test over real HTTP with `app.listen(0)` plus Node's global `fetch`, no new dependency.
- Rabbit holes (looks easy, is not):
  1. Route path. `app.use('/orders', orders)` plus `router.get('/:id')` means `GET /orders/export.csv` lands in the `:id` handler and 404s. Fix without touching `orders.js`: mount the new router in `server.js` *before* the orders router (`app.use('/orders/export.csv', ...)`), or use a sibling path. Decision (assumed): `GET /orders/export.csv`, mounted before the orders router in `server.js`.
  2. CSV escaping. `items` is a nested array; a naive `join(',')` breaks on commas, quotes, or newlines in future data. Gate: RFC 4180 quoting (double any `"`, wrap fields containing `,` `"` `\r` `\n`), CRLF row terminator, and a unit test for a field with a comma and a quote.
  3. Columns. Decision (assumed): `id,userId,status,itemCount,total`. Confirm with the user before adding an `items` column.
- Past incidents on similar work → gate: none found in memory, rules, or task folders.

## 5. Deliverables, in order — each one is a gate before the next
1. **Route decision confirmed** with the user: path `GET /orders/export.csv`, columns `id,userId,status,itemCount,total`, no edit to `orders.js`. Gate: user says yes, or names the owner of `orders.js` if the path must live there. Write the decision to `decisions.md`.
2. **`src/routes/orders-export.js`** (new): `toCsv(orders)` pure function + router. Headers: `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment; filename="orders.csv"`. Gate: `npm run lint` clean.
3. **Mount in `src/server.js`** before `app.use('/orders', orders)`. Gate: `curl -i localhost:3000/orders/export.csv` returns 200 with the header row and two fixture rows; `curl localhost:3000/orders/1` still returns JSON.
4. **`tests/orders-export.test.js`** (new): (a) unit: `toCsv` escapes comma and quote, uses CRLF; (b) HTTP: status 200, content-type `text/csv`, header line, row count = `db.orders.length`, total column equals `GET /orders` JSON total for order 1; (c) existing `/orders/:id` still 200. Gate: `npm test` all green, including the two pre-existing tests.
5. **Docs**: fill `docs/features/csv-export-orders/DEV.md` + `USER.md`; one line in `README.md` after "Try `GET /orders`". Gate: the README line names the exact path.
6. **Commit** by path (`src/routes/orders-export.js`, `src/server.js`, `tests/orders-export.test.js`, `README.md`, `docs/features/csv-export-orders/`, `.task/`). Never stage `node_modules/` or `package-lock.json`. Then move the task folder to `.task/COMPLETED/` and run `/living-docs .task/COMPLETED/csv-export-orders <commit>`.
Acceptance (from "done"): `npm test` green with ≥ 4 new assertions, and a human-run `curl` against `npm start` opens as a two-row spreadsheet with totals 14.99 and 12.50.

## 6. Process
Plan mode. Strongest model = design deliverables; "Plan is firm — switch to the execution model" at the boundary. Counter-proposals before locking. Every mid-task decision → one dated line in `decisions.md` immediately. Coverage claims need traces; every name verified by grep. Reply contract: What → How → Impact, ≤ 3-line blocks.

## 7. Open questions to settle FIRST (ask, don't guess)
1. Hard deadline date, if "next week" means something firmer than 2026-10-28 → user.
2. Who owns `src/routes/orders.js`, in case the user prefers the route inside it → user.
3. Columns: is `id,userId,status,itemCount,total` enough, or must line items appear → user.

## 8. End-to-end verification (the last step, always)
```
npm test && npm run lint
npm start &   # port 3000
curl -si http://localhost:3000/orders/export.csv | tee /tmp/orders-export.txt
curl -s http://localhost:3000/orders/1 | grep -o '"total":[0-9.]*'
```
Expect: `200`, `Content-Type: text/csv; charset=utf-8`, header row, 2 data rows, order 1 total identical in both outputs. Who confirms: the user (sign-off). Artefact kept: `/tmp/orders-export.txt` pasted into `decisions.md` under the commit id.
