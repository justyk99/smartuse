const { computeTotal } = require('../src/routes/orders');

test('sums line items', () => {
  expect(computeTotal([{ qty: 2, price: 10 }])).toBe(20);
});

test('empty order is zero', () => {
  expect(computeTotal([])).toBe(0);
});
