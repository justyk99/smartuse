# CLAUDE.md

Stack: Node 20 + Express 4, Jest, ESLint. In-memory store, no real database.
Run: `npm start` (port 3000).
Test: `npm test`. Lint: `npm run lint`.
Never touch `src/db.js` without asking first.
`src/routes/orders.js` is owned by another developer; tell the user before editing it.
Task folders: `.task/ACTIVE/` while working, `.task/COMPLETED/` once committed.
Feature docs go in `docs/features/`.
