namespace SpecTrace.Demo.Tests;

public class CheckoutTests
{
    [Fact]
    public void CalculateTotal_MultipleItems_ReturnsCorrectSum()
    {
        var items = new[] { (Price: 29.99m, Quantity: 2), (Price: 14.99m, Quantity: 1) };
        var total = OrderCalculator.CalculateTotal(items);
        Assert.Equal(74.97m, total);
    }

    [Fact]
    public void ApplyDiscount_TenPercent_ReturnsCorrectAmount()
    {
        // BUG: floating-point precision — decimal arithmetic should be exact here
        var discounted = OrderCalculator.ApplyDiscount(100.00m, 0.10m);
        Assert.Equal(90.00m, discounted);
    }

    [Fact]
    public void CalculateTotal_EmptyCart_ReturnsZero()
    {
        var total = OrderCalculator.CalculateTotal([]);
        Assert.Equal(0m, total);
    }
}

internal static class OrderCalculator
{
    public static decimal CalculateTotal(IEnumerable<(decimal Price, int Quantity)> items) =>
        items.Sum(i => i.Price * i.Quantity);

    public static decimal ApplyDiscount(decimal subtotal, decimal rate) =>
        Math.Round(subtotal * (1 - rate), 2);
}
