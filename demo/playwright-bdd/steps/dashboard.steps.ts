import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, When, Then } = createBdd();

Given('I am logged in as an admin user', async ({ page }) => {
  await page.goto('/login');
  await page.locator('input[name="email"]').fill('admin@example.com');
  await page.locator('input[name="password"]').fill('AdminPass456');
  await page.locator('button[type="submit"]').click();
  await expect(page).toHaveURL('/dashboard');
});

Given('I navigate to the analytics dashboard', async ({ page }) => {
  await page.locator('[data-testid="nav-analytics"]').click();
  await expect(page).toHaveURL('/analytics');
});

When('I select the date range {string}', async ({ page }, range: string) => {
  await page.locator('[data-testid="date-range-picker"]').click();
  await page.locator(`[data-value="${range}"]`).click();
  await page.locator('[data-testid="apply-date-range"]').click();
});

Then('the daily active users count should be greater than {int}', async ({ page }, threshold: number) => {
  const dauText = await page.locator('[data-testid="dau-metric"]').innerText();
  const dau = parseInt(dauText.replace(/[^0-9]/g, ''), 10);
  expect(dau).toBeGreaterThan(threshold);
});

Then('the chart should display {int} data points', async ({ page }, expectedPoints: number) => {
  const points = page.locator('[data-testid="dau-chart"] [data-testid="chart-point"]');
  await expect(points).toHaveCount(expectedPoints);
});
