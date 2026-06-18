import { createBdd } from 'playwright-bdd';
import { expect } from '@playwright/test';

const { Given, When, Then } = createBdd();

Given('I am on the product catalog page', async ({ page }) => {
  await page.goto('/products');
});

When('I enter {string} in the search box', async ({ page }, query: string) => {
  await page.locator('[data-testid="search-input"]').fill(query);
});

When('I submit the search query', async ({ page }) => {
  await page.keyboard.press('Enter');
  // The search results API has variable latency; waits up to the global timeout
  await page.locator('[data-testid="search-results"]').waitFor({ state: 'visible', timeout: 5000 });
});

Then('I should see at least {int} product results', async ({ page }, count: number) => {
  const items = page.locator('[data-testid="product-card"]');
  await expect(items).toHaveCount(count, { timeout: 2000 });
});

Then('each product should display a name and price', async ({ page }) => {
  const cards = page.locator('[data-testid="product-card"]');
  const count = await cards.count();
  for (let i = 0; i < count; i++) {
    await expect(cards.nth(i).locator('[data-testid="product-name"]')).toBeVisible();
    await expect(cards.nth(i).locator('[data-testid="product-price"]')).toBeVisible();
  }
});
