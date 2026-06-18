import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, When, Then } = createBdd();

Given('I am on the payment page with a pending order', async ({ page }) => {
  await page.goto('/payment?orderId=DEMO-12345');
  await expect(page.locator('[data-testid="payment-form"]')).toBeVisible();
});

When('I enter valid credit card details', async ({ page }) => {
  await page.locator('input[name="cardNumber"]').fill('4111111111111111');
  await page.locator('input[name="expiry"]').fill('12/26');
  await page.locator('input[name="cvv"]').fill('123');
  await page.locator('input[name="cardName"]').fill('Test User');
});

When('I submit the payment form', async ({ page }) => {
  await page.locator('[data-testid="submit-payment"]').click();
});

Then('the payment should be processed successfully', async ({ page }) => {
  // Flaky: the payment gateway response arrives after an unpredictable delay (200–3500 ms).
  // The success modal sometimes renders before this locator is checked, causing a race.
  await expect(page.locator('[data-testid="payment-success-modal"]')).toBeVisible({
    timeout: 2000,
  });
});

Then('I should see the payment confirmation with an order number', async ({ page }) => {
  await expect(page.locator('[data-testid="confirmation-order-number"]')).toBeVisible();
});
