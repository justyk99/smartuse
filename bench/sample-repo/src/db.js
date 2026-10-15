// Fake in-memory store. Replace with a real database later.
const users = [{ id: 1, name: 'Mei', role: 'staff' }];
const orders = [
  { id: 1, userId: 1, items: [{ sku: 'TEA-01', qty: 3, price: 4.995 }], status: 'paid' },
  { id: 2, userId: 1, items: [{ sku: 'MUG-02', qty: 1, price: 12.5 }], status: 'open' }
];

module.exports = {
  users,
  orders,
  findOrder: (id) => orders.find((o) => o.id === id),
  addOrder: (o) => { o.id = orders.length + 1; orders.push(o); return o; }
};
