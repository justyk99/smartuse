cost $0.45 · turns 8 · 1.4 min

**Prompt saved:** `.task/ACTIVE/orders-csv-export/task.md` (703 words, plus `decisions.md`). I also added doc stubs in `docs/features/orders-csv-export/` (`DEV.md` and `USER.md`).
**Self-check:** 14/14 ✓.

**Summary (5 lines, ready to paste)**
- **What:** a new `GET /orders/export.csv` endpoint (address) that returns all orders as a CSV file, one row per order: `id,userId,status,itemCount,total`.
- **Who:** built by Claude, signed off by YK. The file it changes, `src/routes/orders.js`, belongs to `bench`, so they need to OK the edit.
- **When:** aim for Wed 2026-10-21; hard deadline Fri 2026-10-23.
- **Done:** `npm test` and `npm run lint` both pass, and `curl` on the endpoint returns `text/csv` with a header line plus one line per order.
- **Not:** no changes to how totals are rounded, no filters, no login check, no new CSV library, no changes to `src/db.js`.

**Assumed (correct any that are wrong)**
| Slot | Assumption |
|---|---|
| URL | `/orders/export.csv`, declared before `/:id`. Otherwise `/:id` catches it and returns 404. |
| Row shape | One row per order, not one row per item. |
| Test client | Node's built-in `fetch`. `supertest` isn't in the lockfile, so using it means adding a new package. |
| Deadline | 2026-10-23 |
| Time budget | Half a day |

**Open questions to settle first**
1. OK to edit `orders.js`? Answered by `bench`.
2. Row shape and test client? Answered by YK.

**How I checked:** this repo is only 74 lines of code, so I read it directly instead of sending a search agent as the skill says.

**Next:** this is a small task. Say "go" and I'll start with step 1 (getting `bench`'s OK) in plan mode.
`receipt: pending → ledger`