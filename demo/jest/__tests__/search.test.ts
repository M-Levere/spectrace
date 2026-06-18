import { searchProducts } from '../src/search';

describe('Product Search', () => {
  describe('Search by keyword', () => {
    it('returns results for a known keyword', async () => {
      const results = await searchProducts('wireless headphones');
      expect(results.length).toBeGreaterThanOrEqual(5);
    });

    it('returns empty array for unknown keyword', async () => {
      const results = await searchProducts('xyzzy-nonexistent-product-12345');
      expect(results).toEqual([]);
    });

    it('each result has a name and price', async () => {
      // This test times out because the search API is unavailable in this environment
      const results = await searchProducts('laptop');
      results.forEach((r) => {
        expect(r.name).toBeTruthy();
        expect(r.price).toBeGreaterThan(0);
      });
    });
  });
});
