const express = require('express');
const db = require('../db');
const router = express.Router();

// TODO: rounding differs from the invoice service
function computeTotal(items) {
  const sum = items.reduce((t, i) => t + i.qty * i.price, 0);
  return Math.round(sum * 100) / 100;
}

router.get('/', (req, res) => {
  res.json(db.orders.map((o) => ({ ...o, total: computeTotal(o.items) })));
});

router.get('/:id', (req, res) => {
  const o = db.findOrder(Number(req.params.id));
  if (!o) return res.status(404).json({ error: 'not found' });
  res.json({ ...o, total: computeTotal(o.items) });
});

router.post('/', (req, res) => {
  res.status(201).json(db.addOrder({ ...req.body, status: 'open' }));
});

module.exports = { router, computeTotal };
