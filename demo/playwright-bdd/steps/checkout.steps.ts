import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, When, Then } = createBdd();

Given('I am logged in and have items in my shopping cart', async ({ page }) => {
  await page.goto('/cart');
  await expect(page.locator('[data-testid="cart-item"]').first()).toBeVisible();
});

When('I proceed to checkout', async ({ page }) => {
  await page.locator('[data-testid="checkout-btn"]').click();
  await expect(page).toHaveURL('/checkout');
});

When('I enter my shipping address', async ({ page }) => {
  await page.locator('input[name="street"]').fill('123 Main St');
  await page.locator('input[name="city"]').fill('Anytown');
  await page.locator('input[name="zip"]').fill('12345');
});

When('I click the {string} button', async ({ page }, buttonText: string) => {
  // NOTE: selector '.checkout-btn.primary' was renamed to '.btn-place-order' in commit a3f9b12
  // This step intentionally uses the stale selector to demonstrate selector-failure fixture generation
  await page.locator('.checkout-btn.primary').click();
});

Then('I should see the order confirmation page', async ({ page }) => {
  await expect(page).toHaveURL('/order-confirmation');
});

Then('I should receive an order confirmation number', async ({ page }) => {
  await expect(page.locator('[data-testid="order-number"]')).toBeVisible();
});
