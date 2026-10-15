const express = require('express');
const db = require('../db');
const router = express.Router();

router.get('/', (req, res) => res.json(db.users));

router.get('/:id', (req, res) => {
  const u = db.users.find((x) => x.id === Number(req.params.id));
  if (!u) return res.status(404).json({ error: 'not found' });
  res.json(u);
});

module.exports = router;
