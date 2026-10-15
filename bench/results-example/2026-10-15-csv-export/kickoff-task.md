# Orders CSV export — kickoff (2026-10-15, written by /make-prompt, mode: quick)

## Task

### 1. Where things are (verified 2026-10-15)
- Work repo: this repo (`shop-orders-api`), branch `master` (clean). Gates from CLAUDE.md that bite: `src/routes/orders.js` is owned by another developer → tell the user before editing; never touch `src/db.js` without asking.
- Target code: `src/routes/orders.js` (25 lines — `GET /`, `GET /:id`, `POST /`, `computeTotal()`), mounted at `/orders` in `src/server.js` (14 lines, exports `app`). Data: `src/db.js` (13 lines, in-memory `orders` array). Tests: `tests/orders.test.js` (9 lines, unit tests of `computeTotal` only).
- Existing work on the same thing: none found (`.task/`, `docs/features/`, project memory all empty; git log = `baseline`, `deps`).
- Attachments read: none given.

### 2. People, scope split, dates, appetite
- Asked by: YK. Reviewer / sign-off: YK.
- Owner of `src/routes/orders.js`, `src/db.js`, `src/server.js`: `bench` (only git author on all three — verified: `git log --format=%an`). YK's VCS name per adapter = `sample-dev`, so these are NOT YK's files.
- Dates: assumed: target 2026-10-21 (Wed), hard 2026-10-23 (Fri) — "deadline next week".
- Appetite: assumed: half a day. If it runs over, cut: column choice beyond the default set, filtering by status.

### 3. Non-goals (do not build, do not touch)
- No changes to `computeTotal()` rounding (the TODO about the invoice service mismatch stays as is).
- No filters, paging, auth, streaming, or Excel/XLSX output.
- No new npm packages for CSV writing (a ~10-line escaper is enough).
- `src/db.js` → `bench`, untouched.

### 4. Facts that constrain the design + rabbit holes
- Orders are `{ id, userId, items[{sku, qty, price}], status }`; total is computed on read, not stored (verified: `src/db.js`, `docs/ARCHITECTURE.md`).
- No auth on any endpoint today (verified: `docs/ARCHITECTURE.md`) — the export will be open too.
- Rabbit holes:
  - **Route order:** `GET /:id` would swallow `/export.csv` if the new route is declared after it (`Number('export.csv')` → `NaN` → 404). Declare the export route before `/:id`, or mount `/orders.csv` in `server.js`.
  - **No HTTP test client:** `supertest` is not in `package.json` or the lockfile (verified: grep = 0). Adding it changes the lockfile → ask; alternative = start `app.listen(0)` and use Node 20's built-in `fetch`.
  - **CSV escaping + floats:** `items` is an array (needs a flat shape — one row per order with item count, or one row per line item); prices are floats (`3 × 4.995 = 14.985` in JS → `computeTotal` gives `14.99`). Quote fields containing `,` `"` or newlines.
- Past incidents → gate: none found.

### 5. Deliverables, in order — each one is a gate before the next
1. Ask YK + `bench` sign-off to edit `src/routes/orders.js` (or choose the `server.js` mount, also `bench`'s). Gate: written OK.
2. Decide: URL (assumed: `GET /orders/export.csv`), row shape (assumed: one row per order — `id,userId,status,itemCount,total`), test client (assumed: built-in `fetch`, no new dep). Gate: logged in `decisions.md`.
3. Implement route + CSV escaper; `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment; filename="orders.csv"`.
4. Tests in `tests/orders.test.js` (or new `tests/orders-export.test.js`): happy (header + 2 seeded rows, total `14.99` for order 1), escaping (a value with a comma/quote), empty store (header only), `GET /orders/1` still works (route-order regression). Gate: `npm test` + `npm run lint` green.
5. Close-out: `docs/features/orders-csv-export/DEV.md` + `USER.md` via living-docs after commit; task folder → `.task/COMPLETED/`.
Acceptance: `curl -i localhost:3000/orders/export.csv` returns 200, `text/csv`, header line + one line per order; `npm test` and `npm run lint` pass.

### 6. Process
Plan mode. Counter-proposals before locking. Every decision → one dated line in `decisions.md` immediately. Every name verified by grep. Reply contract: What → How → Impact, ≤ 3-line blocks.

### 7. Open questions to settle FIRST (ask, don't guess)
1. OK to edit `src/routes/orders.js`? → `bench` (owner) + YK.
2. Row shape: per order or per line item? → YK.
3. `supertest` as a dev dependency, or built-in `fetch`? → YK.
4. Exact deadline date (assumed 2026-10-23)? → YK.

### 8. End-to-end verification (the last step, always)
`npm start`, then `POST /orders` with `{"userId":"yk, \"1\"","items":[{"sku":"yk-TEA","qty":2,"price":1.5}]}` (userId with a comma + quote, since per-order rows carry no sku), then `curl -i localhost:3000/orders/export.csv` → 3 data rows, the yk row correctly quoted, total `3`. YK confirms; keep the curl output in the commit/PR description.

## Decisions
