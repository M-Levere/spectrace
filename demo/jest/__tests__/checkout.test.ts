import { calculateOrderTotal, applyDiscount } from '../src/checkout';

describe('Shopping Cart Checkout', () => {
  describe('Order total calculation', () => {
    it('calculates total correctly for multiple items', () => {
      const items = [
        { price: 29.99, quantity: 2 },
        { price: 14.99, quantity: 1 },
      ];
      const total = calculateOrderTotal(items);
      expect(total).toBe(74.97);
    });

    it('applies 10% discount correctly', () => {
      const subtotal = 100.00;
      const discounted = applyDiscount(subtotal, 0.10);
      // BUG: applyDiscount returns subtotal - (subtotal * discount) but rounds incorrectly
      // Expected: 90.00, actual: 90.000000001 due to floating-point precision issue
      expect(discounted).toBe(90.00);
    });

    it('returns zero for empty cart', () => {
      const total = calculateOrderTotal([]);
      expect(total).toBe(0);
    });
  });
});
