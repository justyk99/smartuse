# Architecture

- Express app assembled in `src/server.js`; it exports `app` so tests can import it.
- Routes live in `src/routes/`, one file per resource (`orders`, `users`).
- `src/db.js` is a fake in-memory store: plain arrays plus small helper functions.
- No authentication yet; all endpoints are open.
- Order totals are computed on read by `computeTotal()` in `orders.js`.
- Money is stored as JS numbers (floats), not integer cents.
- There is no logging or request tracing today.
- Tests use Jest and sit in `tests/`.
- Feature docs go in `docs/features/`.
- An external invoice service also computes totals; the two can disagree.
