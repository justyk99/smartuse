# Shop Orders API

A small orders back office for a neighbourhood shop. Staff list and create orders, look up customers, and see each order's total. Data lives in memory, so it resets on every restart.

To run it, install dependencies with `npm install` and start the server with `npm start`. It listens on port 3000 (override with `PORT`). Try `GET /orders` and `GET /users`.

To test, run `npm test` (Jest). Run `npm run lint` before sending changes for review.
