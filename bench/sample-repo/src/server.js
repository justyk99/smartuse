const express = require('express');
const { router: orders } = require('./routes/orders');
const users = require('./routes/users');

const app = express();
app.use(express.json());
app.use('/orders', orders);
app.use('/users', users);

if (require.main === module) {
  app.listen(process.env.PORT || 3000, () => console.log('orders API up'));
}

module.exports = app;
