# Decisions — csv-export-orders

- 2026-10-21 — kickoff written by /make-prompt (quick). All slots assumed; see task.md § 2–4 and the open questions in § 7.
- 2026-10-21 — run-plan (safe, --until-done): route decision taken under the kickoff's assumed defaults, pending user sign-off. Path `GET /orders/export.csv` mounted in `src/server.js` before the `/orders` router; columns `id,userId,status,itemCount,total`; `src/routes/orders.js` is not edited (its exported `computeTotal` is reused). Open questions § 7.2 (owner of orders.js) and § 7.3 (line-item column) stay open; neither changes this default. Correct by exception.
- 2026-10-21 — run-plan (safe, --until-done) finished units 1–5: no escalations, no retiers; builds on fable (session model), verify on sonnet (3× "no gaps"), docs on haiku. `npm test` 6/6 green, lint clean. Unit 6 (commit, move folder, /living-docs) left to the user's commit procedure.
