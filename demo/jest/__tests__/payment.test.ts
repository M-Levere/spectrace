import { processPayment, getPaymentStatus } from '../src/payment';

describe('Payment Processing', () => {
  describe('Credit card payment', () => {
    it('returns a confirmation number for valid payment details', async () => {
      const result = await processPayment({
        cardNumber: '4111111111111111',
        expiry: '12/26',
        cvv: '123',
        amount: 74.97,
      });
      expect(result.status).toBe('success');
      expect(result.confirmationNumber).toMatch(/^CONF-[A-Z0-9]{8}$/);
    });

    it('payment status is queryable by confirmation number', async () => {
      const payment = await processPayment({
        cardNumber: '4111111111111111',
        expiry: '12/26',
        cvv: '123',
        amount: 29.99,
      });
      // Flaky: gateway propagation delay means status may not be 'settled' immediately
      const status = await getPaymentStatus(payment.confirmationNumber);
      expect(status).toBe('settled');
    });

    it('rejects expired card', async () => {
      await expect(
        processPayment({ cardNumber: '4111111111111111', expiry: '01/20', cvv: '123', amount: 10 })
      ).rejects.toThrow('Card expired');
    });
  });
});
