namespace SpecTrace.Cli;

public sealed class CliApp(string[] args)
{
    private static readonly string Help = """
        SpecTrace — AI-assisted test intelligence

        Usage:
          spectrace analyze <artifactsDir> [options]   Parse artifacts and diagnose failures
          spectrace init                               Scaffold spectrace.config.yml
          spectrace validate                           Validate config and artifact discovery
          spectrace report                             Re-render a stored JSON report to markdown

        Options for 'analyze':
          --output <file>      Output file path (default: stdout)
          --format md|json     Output format (default: md)
          --config <file>      Config file (default: spectrace.config.yml)
          --no-ai              Heuristic-only run, no model calls
          --code-suggestions   Enable optional code-suggestion engine
          --provider <name>    AI provider: openai|anthropic|gemini|azure|local
          --max-cost <usd>     Per-run cost cap in USD
          --upload             Upload results to dashboard

        Global options:
          --help, -h           Show this help
          --version            Show version
          --verbose            Verbose output

        Exit codes: 0=ok  1=failures-found  2=config/parse-error
        """;

    public Task<int> RunAsync()
    {
        if (args.Length == 0 || args[0] is "--help" or "-h")
        {
            Console.WriteLine(Help);
            return Task.FromResult(0);
        }

        if (args[0] == "--version")
        {
            Console.WriteLine("0.1.0-dev");
            return Task.FromResult(0);
        }

        return args[0] switch
        {
            "analyze"  => RunAnalyzeAsync(),
            "init"     => RunInitAsync(),
            "validate" => RunValidateAsync(),
            "report"   => RunReportAsync(),
            _ => UnknownCommand(args[0]),
        };
    }

    private static Task<int> RunAnalyzeAsync()
    {
        Console.Error.WriteLine("'analyze' command not yet implemented (Phase 2).");
        return Task.FromResult(2);
    }

    private static Task<int> RunInitAsync()
    {
        Console.Error.WriteLine("'init' command not yet implemented (Phase 2).");
        return Task.FromResult(2);
    }

    private static Task<int> RunValidateAsync()
    {
        Console.Error.WriteLine("'validate' command not yet implemented (Phase 2).");
        return Task.FromResult(2);
    }

    private static Task<int> RunReportAsync()
    {
        Console.Error.WriteLine("'report' command not yet implemented (Phase 2).");
        return Task.FromResult(2);
    }

    private static Task<int> UnknownCommand(string cmd)
    {
        Console.Error.WriteLine($"Unknown command: {cmd}");
        Console.Error.WriteLine("Run 'spectrace --help' for usage.");
        return Task.FromResult(2);
    }
}
