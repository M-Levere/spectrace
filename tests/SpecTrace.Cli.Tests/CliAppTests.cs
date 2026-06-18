using SpecTrace.Cli;

namespace SpecTrace.Cli.Tests;

public class CliAppTests
{
    [Fact]
    public async Task No_args_exits_zero_and_prints_help()
    {
        var stdout = new StringWriter();
        var prev = Console.Out;
        Console.SetOut(stdout);
        try
        {
            var exit = await new CliApp([]).RunAsync();
            Assert.Equal(0, exit);
            Assert.Contains("spectrace", stdout.ToString(), StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Console.SetOut(prev);
        }
    }

    [Fact]
    public async Task Help_flag_exits_zero()
    {
        var exit = await new CliApp(["--help"]).RunAsync();
        Assert.Equal(0, exit);
    }

    [Fact]
    public async Task Unknown_command_exits_two()
    {
        var exit = await new CliApp(["bogus"]).RunAsync();
        Assert.Equal(2, exit);
    }
}
