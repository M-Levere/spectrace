import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, When, Then } = createBdd();

Given('I am on the login page', async ({ page }) => {
  await page.goto('/login');
  await expect(page.locator('form[data-testid="login-form"]')).toBeVisible();
});

When('I enter username {string}', async ({ page }, username: string) => {
  await page.locator('input[name="email"]').fill(username);
});

When('I enter password {string}', async ({ page }, password: string) => {
  await page.locator('input[name="password"]').fill(password);
});

When('I click the login button', async ({ page }) => {
  await page.locator('button[type="submit"]').click();
});

Then('I should be redirected to the dashboard', async ({ page }) => {
  await expect(page).toHaveURL('/dashboard');
});

Then('I should see the welcome message {string}', async ({ page }, message: string) => {
  await expect(page.locator('[data-testid="welcome-banner"]')).toContainText(message);
});
