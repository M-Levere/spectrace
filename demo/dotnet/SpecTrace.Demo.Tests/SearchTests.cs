namespace SpecTrace.Demo.Tests;

public class SearchTests
{
    [Fact]
    public async Task SearchByKeyword_KnownProduct_ReturnsResults()
    {
        var svc = new FakeProductSearch();
        var results = await svc.SearchAsync("wireless headphones");
        Assert.True(results.Count >= 5);
    }

    [Fact]
    public async Task SearchByKeyword_UnknownProduct_ReturnsEmpty()
    {
        var svc = new FakeProductSearch();
        var results = await svc.SearchAsync("xyzzy-nonexistent-12345");
        Assert.Empty(results);
    }

    [Fact(Timeout = 1000)]
    public async Task SearchByKeyword_SlowApi_TimesOut()
    {
        // This test demonstrates a timeout scenario:
        // The search service has 2 s latency but the test timeout is 1 s.
        var svc = new SlowProductSearch(latencyMs: 2000);
        var results = await svc.SearchAsync("laptop");
        Assert.True(results.Count > 0);
    }
}

internal record Product(string Name, decimal Price);

internal class FakeProductSearch
{
    public Task<List<Product>> SearchAsync(string query)
    {
        if (query == "wireless headphones")
            return Task.FromResult(Enumerable.Range(1, 8)
                .Select(i => new Product($"Headphones Model {i}", 49.99m + i))
                .ToList());
        return Task.FromResult(new List<Product>());
    }
}

internal class SlowProductSearch(int latencyMs)
{
    public async Task<List<Product>> SearchAsync(string query)
    {
        await Task.Delay(latencyMs);
        return [new Product("Laptop Pro", 999.00m)];
    }
}
