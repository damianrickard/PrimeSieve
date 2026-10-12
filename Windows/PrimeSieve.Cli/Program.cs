using PrimeSieve.Core;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cancellation.Cancel(); };
try
{
    var command = args.FirstOrDefault() ?? "list";
    if (command is "help" or "--help")
    {
        Console.WriteLine("PrimeSieve CLI: list | verify | run [--languages csharp,fsharp,python,javascript] [--count 100000] [--iterations 7] [--warmups 3] [--timeout 120] [--startup] [--output results.json]"); return 0;
    }
    string? Option(string flag) { var i = Array.IndexOf(args, flag); return i < 0 ? null : i + 1 < args.Length ? args[i + 1] : throw new ArgumentException("Missing value for " + flag); }
    var preferences = new SessionStore().LoadRuntimePreferences();
    foreach (var warning in preferences.Warnings) Console.Error.WriteLine("Warning: " + warning);
    var overrides = preferences.Paths;
    var statuses = await RuntimeDiscovery.DiscoverAsync(overrides, cancellation.Token);
    if (command == "list")
    {
        foreach (var status in statuses) Console.WriteLine($"{status.Language.Id,-12} {(status.Available ? "Detected" : "Unavailable"),-12} {status.Version} {status.Executable}"); return 0;
    }
    var ids = Option("--languages")?.Split(',');
    if (ids != null && ids.Any(id => !statuses.Any(s => s.Language.Id == id && s.Available)))
        throw new ArgumentException("An unknown or unavailable language was selected.");
    var selected = statuses.Where(s => s.Available && (ids == null || ids.Contains(s.Language.Id))).ToArray();
    if (command == "verify")
    {
        foreach (var count in new[] { 1, 2, 5, 1000 })
        {
            var verification = await BenchmarkRunner.RunAsync(selected, new(count, 2, 1), overrides, cancellationToken: cancellation.Token);
            foreach (var result in verification.Results) Console.WriteLine($"PASS {result.Language}: N={count}, last={result.Signature.LastPrime}");
            foreach (var failure in verification.Failures) Console.Error.WriteLine($"FAIL {failure.Key}: {failure.Value}");
            if (verification.Cancelled || verification.Failures.Count > 0) return 1;
        }
        return 0;
    }
    if (command != "run") throw new ArgumentException("Unknown command. Use --help.");
    var configuration = new BenchmarkConfiguration(int.Parse(Option("--count") ?? "100000"), int.Parse(Option("--iterations") ?? "7"),
        int.Parse(Option("--warmups") ?? "3"), double.Parse(Option("--timeout") ?? "120", System.Globalization.CultureInfo.InvariantCulture), args.Contains("--startup") ? TimingMode.Startup : TimingMode.Calculation);
    var session = await BenchmarkRunner.RunAsync(selected, configuration, overrides, cancellationToken: cancellation.Token);
    foreach (var result in session.Results) Console.WriteLine($"{result.Language,-14} median {result.MedianDisplay,-12} mean {result.MeanDisplay,-12} {result.Iterations} samples • verified");
    foreach (var failure in session.Failures) Console.Error.WriteLine($"FAIL {failure.Key}: {failure.Value}");
    if (Option("--output") is { } output) SessionStore.ExportJson(session, output);
    return session.Cancelled || session.Failures.Count > 0 ? 1 : 0;
}
catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
