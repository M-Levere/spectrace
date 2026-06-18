namespace SpecTrace.Demo.Tests;

public class LoginTests
{
    [Fact]
    public void ValidCredentials_ReturnsSessionToken()
    {
        var auth = new FakeAuthService();
        var result = auth.Login("test@example.com", "SecurePass123");
        Assert.NotNull(result.Token);
        Assert.Equal("user-001", result.UserId);
    }

    [Fact]
    public void ValidCredentials_ReturnsCorrectWelcomeMessage()
    {
        var auth = new FakeAuthService();
        var session = auth.Login("test@example.com", "SecurePass123");
        Assert.Equal("Welcome back, Test User", auth.GetWelcomeMessage(session.UserId));
    }

    [Fact]
    public void ValidCredentials_SetsSessionExpiry()
    {
        var auth = new FakeAuthService();
        var result = auth.Login("test@example.com", "SecurePass123");
        Assert.Equal(3600, result.ExpiresIn);
    }
}

internal record LoginResult(string Token, string UserId, int ExpiresIn);

internal class FakeAuthService
{
    public LoginResult Login(string email, string password)
    {
        if (email == "test@example.com" && password == "SecurePass123")
            return new LoginResult("tok_abc123", "user-001", 3600);
        throw new UnauthorizedAccessException("Invalid credentials");
    }

    public string GetWelcomeMessage(string userId) =>
        userId == "user-001" ? "Welcome back, Test User" : "Welcome back";
}
