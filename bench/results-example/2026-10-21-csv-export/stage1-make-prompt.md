cost $1.57 · turns 6 · 2.4 min

**Prompt saved:** `.task/ACTIVE/csv-export-orders/task.md` (1,018 words, plus `research.md` and `decisions.md` beside it; living-docs stubs in `docs/features/csv-export-orders/`).
Self-check: 14/14 ✓. No ✗ items. Repo is the right one, no past incidents or prior work found, no attachments to read.

**Summary**
- What: `GET /orders/export.csv` returns all orders as an RFC 4180 CSV download, totals identical to the JSON API, plus a Jest HTTP test with no new dependencies.
- Who: built and signed off by you. The owner of `src/routes/orders.js` is not touched because the new router mounts in `server.js` ahead of the orders router.
- When: target 2026-10-28, review 2026-10-27, appetite one day.
- Done: `npm test` green with the new assertions, and a `curl` against the running server yields a two-row CSV whose order 1 total matches `GET /orders/1`.
- Not: no filters or pagination, no rounding fix, no Accept-header negotiation, no line-item rows, no edits to `db.js` or `orders.js`.

**Assumed (correct by exception)**
- Target date 2026-10-28 from "next week". Hard date unknown, you answer.
- Route path `GET /orders/export.csv`, mounted in `server.js` before the orders router. Alternative inside `orders.js` needs that file's owner named.
- Columns `id,userId,status,itemCount,total`, one row per order.
- Test over real HTTP with `app.listen(0)` and Node's built-in fetch instead of adding supertest. This keeps the untracked lockfile out of the change.
- Appetite one day. If over, drop the download header and the live smoke test.

**Rabbit holes flagged in the prompt:** the `/:id` route swallowing `export.csv`, CSV escaping of commas and quotes, and the float total on the 4.995 fixture.

Next step: small task, so say "go" and I start deliverable 1 in plan mode here. Also worth setting `/goal npm test green with the CSV export test` so the session cannot stop early.

receipt: pending → ledger