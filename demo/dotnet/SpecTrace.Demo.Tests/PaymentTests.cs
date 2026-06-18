namespace SpecTrace.Demo.Tests;

public class PaymentTests
{
    [Fact]
    public async Task ValidCard_ReturnsConfirmationNumber()
    {
        var svc = new FakePaymentGateway(successDelayMs: 0);
        var result = await svc.ProcessAsync("4111111111111111", "12/26", "123", 74.97m);
        Assert.Equal("success", result.Status);
        Assert.Matches(@"^CONF-[A-Z0-9]{8}$", result.ConfirmationNumber);
    }

    [Fact]
    public async Task PaymentStatus_AfterProcessing_IsSettled()
    {
        // Flaky: the gateway propagates 'settled' status after a random delay (0–500 ms).
        // On slow CI runners this test fails intermittently because the status query
        // races the propagation window.
        var svc = new FakePaymentGateway(successDelayMs: Random.Shared.Next(0, 500));
        var payment = await svc.ProcessAsync("4111111111111111", "12/26", "123", 29.99m);
        var status = await svc.GetStatusAsync(payment.ConfirmationNumber);
        Assert.Equal("settled", status);
    }

    [Fact]
    public async Task ExpiredCard_ThrowsException()
    {
        var svc = new FakePaymentGateway(successDelayMs: 0);
        await Assert.ThrowsAsync<InvalidOperationException>(() =>
            svc.ProcessAsync("4111111111111111", "01/20", "123", 10m));
    }
}

internal record PaymentResult(string Status, string ConfirmationNumber);

internal class FakePaymentGateway(int successDelayMs)
{
    private readonly Dictionary<string, string> _statuses = new();

    public async Task<PaymentResult> ProcessAsync(string card, string expiry, string cvv, decimal amount)
    {
        if (IsExpired(expiry))
            throw new InvalidOperationException("Card expired");

        await Task.Delay(successDelayMs);
        var confirmation = $"CONF-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}";
        _statuses[confirmation] = "settled";
        return new PaymentResult("success", confirmation);
    }

    public async Task<string> GetStatusAsync(string confirmationNumber)
    {
        await Task.Delay(1);
        return _statuses.TryGetValue(confirmationNumber, out var s) ? s : "unknown";
    }

    private static bool IsExpired(string expiry)
    {
        var parts = expiry.Split('/');
        if (parts.Length != 2) return true;
        var month = int.Parse(parts[0]);
        var year = 2000 + int.Parse(parts[1]);
        return new DateTime(year, month, 1).AddMonths(1) < DateTime.UtcNow;
    }
}
