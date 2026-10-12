using System.Diagnostics;
using System.Text.Json;
using PrimeSieve.Core;

// Dependency-free regression executable, runnable on both Windows and macOS.
if (args.Contains("-XshowSettings:properties"))
{
    Console.Error.WriteLine("    java.home = " + Environment.GetEnvironmentVariable("PRIMESIEVE_TEST_JAVA_HOME")); return 0;
}
if (args.FirstOrDefault() is "--spawn-child" or "--spawn-child-exit")
{
    var info = new ProcessStartInfo(args[1]) { UseShellExecute = false };
    info.ArgumentList.Add(typeof(Program).Assembly.Location); info.ArgumentList.Add("--sleep");
    using var child = Process.Start(info)!;
    File.WriteAllText(args[2], child.Id.ToString());
    if (args[0] == "--spawn-child") await Task.Delay(30000); return 0;
}
if (args.FirstOrDefault() == "--sleep") { await Task.Delay(30000); return 0; }
if (args.FirstOrDefault() == "--flood") { Console.Write(new string('x', 1_100_000)); return 0; }
if (args.FirstOrDefault() == "--fail") { Console.Error.Write("expected failure"); return 7; }
if (args.FirstOrDefault() == "--echo") { Console.Write(args[1]); return 0; }
if (args.FirstOrDefault() == "--echo-json") { Console.Write(JsonSerializer.Serialize(args[1])); return 0; }
var passed = 0;
void Check(bool condition, string name) { if (!condition) throw new Exception("FAIL " + name); passed++; Console.WriteLine("PASS " + name); }
void Throws(Action action, string name) { try { action(); } catch { Check(true, name); return; } throw new Exception("FAIL " + name); }
async Task ThrowsAsync<T>(Func<Task> action, string name) where T : Exception
{ try { await action(); } catch (T) { Check(true, name); return; } throw new Exception("FAIL " + name); }
var root = Path.Combine(Path.GetTempPath(), "PrimeSieve-tests-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
try
{
    foreach (var (count, last, sum) in new[] { (1, 2, 2L), (2, 3, 5L), (5, 11, 28L), (1000, 7919, 3682913L), (10000, 104729, 496165411L) })
        Check(PrimeReference.Calculate(count, new BenchmarkConfiguration(count).SieveLimit) == new PrimeSignature(count, last, sum), "independent reference " + count);
    foreach (var config in new[] { new BenchmarkConfiguration(0), new BenchmarkConfiguration(10_000_001), new BenchmarkConfiguration(Repetitions: 0), new BenchmarkConfiguration(Repetitions: 31), new BenchmarkConfiguration(Warmups: -1), new BenchmarkConfiguration(Warmups: 21), new BenchmarkConfiguration(TimeoutSeconds: double.NaN), new BenchmarkConfiguration(TimeoutSeconds: double.PositiveInfinity), new BenchmarkConfiguration(Mode: (TimingMode)99) })
        Throws(config.Validate, "configuration boundary");
    Check(SieveImplementation.All.Length == 43 && SieveImplementation.All.Select(i => i.Id).Distinct().Count() == 43, "unique implementation registry");
    Check(ReferenceEquals(SieveImplementation.All, SieveImplementation.All) && SieveImplementation.RegistryError == null, "registry is cached");
    SieveImplementation.ValidateRegistry();
    var registryFixture = Path.Combine(root, "implementations.json");
    void CheckInvalidRegistry()
    {
        var loaded = SieveImplementation.LoadRegistry(registryFixture);
        Check(loaded.Error?.StartsWith("Unable to load implementation registry") == true && loaded.Implementations.Length == 35 && loaded.Implementations.All(i => i.IsBaseline), "damaged registry reports error and preserves baselines");
    }
    CheckInvalidRegistry();
    var variant = SieveImplementation.All.First(i => !i.IsBaseline);
    foreach (var text in new[] { "{broken", "null", "[]", "[null]", "[{}]",
        JsonSerializer.Serialize(new[] {variant, variant},JsonDefaults.Options),
        JsonSerializer.Serialize(new[] {variant with {LanguageID = "unknown"}},JsonDefaults.Options),
        JsonSerializer.Serialize(new[] {variant with {ProtocolVersion = 1}},JsonDefaults.Options) })
    { File.WriteAllText(registryFixture, text); CheckInvalidRegistry(); }
    File.WriteAllText(registryFixture, JsonSerializer.Serialize(new[] {variant},JsonDefaults.Options));
    Check(SieveImplementation.LoadRegistry(registryFixture) is { Error:null, Implementations.Length:36 }, "valid registry loads alongside baselines");
    foreach (var item in SieveImplementation.All.Where(i => !i.IsBaseline)) Check(WorkerSources.Sections(item).Length > 0 && item.Files().All(f => File.Exists(WorkerSources.PathFor(f))), "variant sources " + item.Id);
    foreach (var limit in new[] {2,3,4,8,9,24,25,26,48,49,50,63,64,65,127,128,129,1024})
    {
        var expected = PrimeReference.Sequence(int.MaxValue, limit);
        Check(PrimeReference.Calculate(new(Workload:Workload.UpperLimit,UpperLimit:limit)) == new PrimeSignature(expected.Length,expected[^1],expected.Sum(x => (long)x)), "inclusive limit " + limit);
    }
    Throws(() => new BenchmarkConfiguration(Mode:TimingMode.Throughput).Validate(), "throughput requires limit workload");
    Throws(() => new BenchmarkConfiguration(Rounds:0).Validate(), "round count boundary");
    new BenchmarkConfiguration(PrimeCount:100,UpperLimit:0).Validate();
    new BenchmarkConfiguration(PrimeCount:0,Workload:Workload.UpperLimit,UpperLimit:1024).Validate();
    Check(true, "inactive workload values do not block validation");
    Throws(() => new BenchmarkConfiguration(Workload:Workload.UpperLimit,UpperLimit:0).Validate(), "active upper limit remains validated");
    var tightBudget = new BenchmarkConfiguration(Repetitions:23,Warmups:3,TimeoutSeconds:120,Mode:TimingMode.Throughput,Workload:Workload.UpperLimit,UpperLimit:200_000_000,DurationSeconds:5);
    tightBudget.Validate();
    Check(tightBudget.TimeoutSeconds == 120 && tightBudget.SuggestedThroughputTimeout == 230, "timeout guidance preserves user budget");
    Check(new[] { "startup", "warm-ups", "final-pass overrun", "verification", "output", "not a completion guarantee" }.All(term => tightBudget.TimeoutGuidance!.Contains(term)), "timeout guidance describes overhead and uncertainty");
    Throws(() => (tightBudget with { TimeoutSeconds = 115 }).Validate(), "timeout must exceed window total");
    Check(new BenchmarkConfiguration(Repetitions:1).SuggestedThroughputTimeout == 30 && new BenchmarkConfiguration().TimeoutGuidance == null, "timeout suggestion floor and timing mode");
    Check(Statistics.Iqr([1,2,3,4]) == 1.5 && new MeasurementWindow(10,5e9,2).PassesPerSecondPerThread == 1, "IQR and per-thread rates");
    const string window = """{"elapsed_ns":20000000,"count":2,"last_prime":3,"checksum":5,"passes":20,"primes":[2,3]}""";
    Check(BenchmarkRunner.Decode(window,1,new(2,3,5),[2,3],0.02).Length == 1, "verified duration window");
    foreach (var invalid in new[] { window.Replace("20000000","1000"),window.Replace("\"passes\":20","\"passes\":0"),window.Replace("[2,3]","[1,4]") })
        Throws(() => BenchmarkRunner.Decode(invalid,1,new(2,3,5),[2,3],0.02), "bad window rejected");
    var signature = new PrimeSignature(1, 2, 2);
    const string good = "{\"elapsed_ns\":1.5,\"count\":1,\"last_prime\":2,\"checksum\":2}";
    Check(BenchmarkRunner.Decode("runtime banner\n" + good, 1, signature)[0].ElapsedNS == 1.5, "decode banner and valid sample");
    foreach (var bad in new[] { good.Replace("1.5", "-1"), good.Replace("1.5", "1e999"), good.Replace("\"checksum\":2", "\"checksum\":3"), "{broken", "{}", "" })
        Throws(() => BenchmarkRunner.Decode(bad, 1, signature), "reject malformed or unverified timing");
    Throws(() => BenchmarkRunner.Decode(good + "\n" + good, 1, signature), "reject extra samples");
    var result = new BenchmarkResult("csharp", "C#", "test", "test.exe", [9, 1, 5, 3], 0, signature, [], [], "abc", [], []);
    Check(result.MedianNS == 4 && result.MeanNS == 4.5 && result.MinimumNS == 1 && result.MaximumNS == 9 && result.Iterations == 4, "statistics exclude no stored samples");
    Check((result with { SamplesNS = [5] }).MedianNS == 5, "single iteration");
    Check(Language.All.Length == 35 && Language.All.Select(l => l.Id).Distinct().Count() == 35, "35 unique languages");
    foreach (var language in Language.All) Check(WorkerSources.Sections(language).Length >= 1, "code explorer " + language.Name);
    Throws(() => WorkerSources.Parse("// PRIME-BEGIN: Outer\n// PRIME-BEGIN: Inner"), "nested markers fail visibly");
    Throws(() => WorkerSources.Parse("// PRIME-BEGIN: Missing end\ncode"), "incomplete markers fail visibly");
    File.WriteAllText(Path.Combine(root, "a"), "bc"); File.WriteAllText(Path.Combine(root, "ab"), "c");
    Check(WorkerSources.Hash(["a"], root) != WorkerSources.Hash(["ab"], root), "length-prefixed source manifest");
    Check(WorkerSources.Hash(["a", "ab"], root) == WorkerSources.Hash(["ab", "a"], root), "source manifest stable ordering");
    var store = new SessionStore(Path.Combine(root, "store"));
    var session = new BenchmarkSession { Configuration = new(1), Completed = true }; session.Results.Add(result);
    store.Save(session); Check(store.Load().Sessions.Single().Results[0].MeanNS == 4.5, "history round-trip");
    var historyPath = Path.Combine(store.Root,"Sessions",session.Id + ".json");
    var historyDocument = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(historyPath))!;
    historyDocument["configuration"]!.AsObject().Remove("contractVersion"); File.WriteAllText(historyPath,historyDocument.ToJsonString());
    Check(store.Load().Sessions.Single().Configuration.ContractVersion == 1, "legacy history retains contract v1");
    historyDocument["results"]![0]!.AsObject().Remove("signature"); File.WriteAllText(historyPath,historyDocument.ToJsonString());
    Check(store.Load().Errors.Count == 1, "missing signature skipped safely"); store.Save(session);

    File.WriteAllText(Path.Combine(store.Root, "Sessions", Guid.NewGuid() + ".json"), "invalid");
    Check(store.Load().Errors.Count == 1 && store.Load().Sessions.Count == 1, "corrupt history isolated");
    File.WriteAllText(Path.Combine(store.Root, "Sessions", "keep.json"), "not a session");
    store.Clear(); Check(File.Exists(Path.Combine(store.Root, "Sessions", "keep.json")) && store.Load().Sessions.Count == 0, "history clear preserves unrelated files");
    var csv = Path.Combine(root, "results.csv"); session.Results[0] = result with { RuntimeVersion = "=HYPERLINK(\"x\")" }; SessionStore.ExportCsv(session, csv);
    Check(File.ReadAllText(csv).Contains("'" + "=HYPERLINK") && File.ReadAllText(csv).Contains("samples_ns"), "CSV retains raw samples and neutralizes formulas");
    Check(RuntimeDiscovery.Find(["dotnet"], new Dictionary<string, string> { ["csharp"] = Path.Combine(root, "missing.exe") }, "csharp") == null, "missing override never falls back");
    var settings = Path.Combine(store.Root, "runtimes.json");
    File.WriteAllText(settings, "{broken");
    var preferences = store.LoadRuntimePreferences();
    Check(preferences.Paths.Count == 0 && preferences.Warnings.Count == 1 && File.ReadAllText(settings) == "{broken", "malformed runtime settings recover without overwriting evidence");
    File.WriteAllText(settings, JsonSerializer.Serialize(new Dictionary<string, string?> { ["c"] = null, ["python"] = " ", ["java"] = "relative", ["csharp"] = Path.Combine(root, "missing.exe") }));
    preferences = store.LoadRuntimePreferences();
    Check(preferences.Paths.Count == 1 && preferences.Warnings.Count == 3 && preferences.Paths.ContainsKey("csharp"), "invalid runtime settings filtered while explicit missing paths are preserved");
    File.WriteAllText(settings, "null");
    Check(store.LoadRuntimePreferences().Warnings.Count == 1, "null preferences document recovers");
    File.Delete(settings); Directory.CreateDirectory(settings);
    Check(store.LoadRuntimePreferences().Warnings.Count == 1, "unreadable settings recover"); Directory.Delete(settings);
    Check(RuntimeDiscovery.Find(["dotnet"], new Dictionary<string, string> { ["csharp"] = null! }, "csharp") == null, "null override cannot abort discovery");
    var python = (await RuntimeDiscovery.DiscoverAsync()).Where(s => s.Available && s.Language.Id == "python").ToArray();
    if (python.Length > 0) foreach (var mode in new[] { TimingMode.Calculation, TimingMode.Startup, TimingMode.Throughput })
    {
        var comparison = await BenchmarkRunner.RunAsync(python, new(129,2,1, Mode:mode, Workload:Workload.UpperLimit,UpperLimit:129,DurationSeconds:0.02,Rounds:2,Implementations:ImplementationSelection.Candidates,ContractVersion:1));
        Check(comparison.Failures.Count == 0 && comparison.Results.Count == 1 && comparison.Results[0].SamplesNS.Length == 4 && comparison.Configuration.ContractVersion == 3, "variant integration " + mode);
        Check(comparison.ExecutionOrder.Count == 2 && comparison.Results[0].RoundOrders!.SequenceEqual(new[] {1,2}), "round metadata " + mode);
        Check(comparison.Results[0].IsThroughput == (mode == TimingMode.Throughput), "score mode " + mode);
        Check(comparison.Results[0].LaunchCommand.Last() == (mode == TimingMode.Startup ? "0" : "1"), "startup samples exclude full-sequence output " + mode);
    }
    if (python.Length > 0) foreach (var interruptedRound in new[] {1,2})
    {
        using var cancel = new CancellationTokenSource();
        var snapshots = new List<BenchmarkResult[]>();
        var progress = new InlineProgress(update => {
            if (update.CompletedRoundResults is {} complete) snapshots.Add(complete);
            if (update.Result?.RoundOrders?.Last() == interruptedRound) cancel.Cancel();
        });
        var partial = await BenchmarkRunner.RunAsync(python, new(Repetitions:2,Warmups:0,Workload:Workload.UpperLimit,UpperLimit:129,Rounds:3,Implementations:ImplementationSelection.All),progress:progress,cancellationToken:cancel.Token);
        Check(partial.Cancelled && !partial.Completed && snapshots.Count == interruptedRound-1, "cancellation only publishes complete rounds " + interruptedRound);
        Check(partial.Results.Count == (interruptedRound == 1 ? 0 : 2) && partial.Results.All(r => r.RoundOrders!.SequenceEqual(new[] {1}) && r.SamplesNS.Length == 2), "partial-round samples rolled back " + interruptedRound);
        var partialStore = new SessionStore(Path.Combine(root,"cancel-round-"+interruptedRound)); partialStore.Save(partial);
        Check(partialStore.Load().Sessions.Single().Results.All(r => r.RoundOrders!.SequenceEqual(new[] {1}) && r.SamplesNS.Length == 2), "cancelled round snapshot persists " + interruptedRound);
    }
    if (python.Length > 0)
    {
        var largeSequence = await BenchmarkRunner.RunAsync(python, new(Repetitions:30,Warmups:0,Workload:Workload.UpperLimit,UpperLimit:100000,Implementations:ImplementationSelection.Candidates));
        Check(largeSequence.Failures.Count == 0 && largeSequence.Results.Single().SamplesNS.Length == 30, "full-sequence output fits at maximum repetition count");
    }
    var suffix = OperatingSystem.IsWindows() ? ".exe" : "";
    var jdk = Path.Combine(root, "actual jdk"); var bin = Path.Combine(jdk, "bin"); Directory.CreateDirectory(bin);
    File.WriteAllText(Path.Combine(bin, "java" + suffix), "fixture"); File.WriteAllText(Path.Combine(bin, "javac" + suffix), "fixture");
    Check(Toolchain.JavaHomeFromProperties("banner\n    java.home = " + jdk + "\n") == jdk, "JDK home is validated from JVM properties");
    Check(Toolchain.JavaHomeFromProperties("java.home = " + Path.Combine(jdk, "jre")) == jdk, "JDK 8 nested JRE home");
    Throws(() => Toolchain.JavaHomeFromProperties("java.home = " + root), "JRE or invalid home rejected");
    Throws(() => Toolchain.JavaHomeFromProperties("no property"), "missing JVM home rejected");
    var dotnet = RuntimeDiscovery.Find(["dotnet"]) ?? throw new Exception(".NET required for process tests.");
    var assembly = typeof(Program).Assembly.Location;
    Check((await ProcessExecutor.RunAsync(dotnet, [assembly, "--echo", "a path with spaces & symbols"])).Stdout == "a path with spaces & symbols", "direct process argument preservation");
    foreach (var argument in new[] { "", "tail with space\\", "embedded\"quote", "slashes\\\\\"quote", "λ 日本語", "C:\\plain\\" })
        Check(JsonSerializer.Deserialize<string>((await ProcessExecutor.RunAsync(dotnet, [assembly, "--echo-json", argument])).Stdout) == argument, "native argument quoting: " + argument);
    var blockedContext = new QueuedContext();
    var previousContext = SynchronizationContext.Current;
    Task<ProcessOutput> detached;
    SynchronizationContext.SetSynchronizationContext(blockedContext);
    try { detached = ProcessExecutor.RunAsync(dotnet, [assembly, "--echo", "unblocked"]); }
    finally { SynchronizationContext.SetSynchronizationContext(previousContext); }
    try
    {
        Check((await detached.WaitAsync(TimeSpan.FromSeconds(10))).Stdout == "unblocked" && blockedContext.PostCount == 0, "process completion and elapsed timing do not depend on caller UI dispatch");
    }
    finally { blockedContext.Drain(); }
    await ThrowsAsync<IOException>(() => ProcessExecutor.RunAsync(dotnet, [assembly, "--fail"]), "nonzero exit surfaced");
    await ThrowsAsync<IOException>(() => ProcessExecutor.RunAsync(dotnet, [assembly, "--flood"]), "bounded worker output");
    var watch = Stopwatch.StartNew();
    await ThrowsAsync<TimeoutException>(() => ProcessExecutor.RunAsync(dotnet, [assembly, "--sleep"], timeoutSeconds: .3), "worker timeout");
    Check(watch.Elapsed.TotalSeconds < 7, "timeout returns promptly");
    using (var cancel = new CancellationTokenSource(200))
        await ThrowsAsync<OperationCanceledException>(() => ProcessExecutor.RunAsync(dotnet, [assembly, "--sleep"], cancellationToken: cancel.Token), "worker cancellation");
    using (var cancel = new CancellationTokenSource())
    {
        cancel.Cancel();
        var statuses = new[] { new RuntimeStatus(Language.All.First(l => l.Id == "csharp"), dotnet, "test") };
        var cancelled = await BenchmarkRunner.RunAsync(statuses, new(), cancellationToken: cancel.Token);
        Check(cancelled.Cancelled && !cancelled.Completed && cancelled.Results.Count == 0, "cancelled session returned for persistence");
    }
    if (OperatingSystem.IsWindows())
    {
        var batch = Path.Combine(root, "echo test.cmd"); File.WriteAllText(batch, "@echo off\r\necho %~1\r\n");
        Check((await ProcessExecutor.RunAsync(batch, ["path with spaces"])).Stdout.Trim() == "path with spaces", "Windows batch wrapper quoting");
        await ThrowsAsync<ArgumentException>(() => ProcessExecutor.RunAsync(batch, ["unsafe&command"]), "Windows batch metacharacters rejected");
    }
    if (OperatingSystem.IsWindows())
    {
        var pidFile = Path.Combine(root, "child.pid");
        await ThrowsAsync<TimeoutException>(() => ProcessExecutor.RunAsync(dotnet, [assembly, "--spawn-child", dotnet, pidFile], timeoutSeconds: 1), "process tree timeout");
        var pid = int.Parse(File.ReadAllText(pidFile));
        var childExited = false;
        try { using var child = Process.GetProcessById(pid); childExited = child.HasExited || child.WaitForExit(3000); }
        catch (ArgumentException) { childExited = true; }
        Check(childExited, "Windows child process terminated");
    }
    if (OperatingSystem.IsWindows())
    {
        // An immediate cmd exit used to race the post-Start job assignment.
        var cmd = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
        for (var attempt = 0; attempt < 25; attempt++)
            await ProcessExecutor.RunAsync(cmd, ["/d", "/c", "exit", "0"], timeoutSeconds: 5);
        Check(true, "25 immediate Windows exits do not race containment");
        var pidFile = Path.Combine(root, "orphan.pid");
        try { await ProcessExecutor.RunAsync(dotnet, [assembly, "--spawn-child-exit", dotnet, pidFile], timeoutSeconds: 2); }
        catch (TimeoutException) { } // Inherited stdout keeps the pipe open until the job is cancelled.
        var pid = int.Parse(File.ReadAllText(pidFile));
        var exited = false;
        try { using var child = Process.GetProcessById(pid); exited = child.HasExited || child.WaitForExit(3000); }
        catch (ArgumentException) { exited = true; }
        Check(exited, "child remains contained after its immediate parent exits");

        var alias = Path.Combine(root, "javapath"); Directory.CreateDirectory(alias);
        // A real apphost stands in for Oracle's executable shim; it reports an unrelated JDK home.
        foreach (var file in Directory.EnumerateFiles(AppContext.BaseDirectory).Where(f => f.EndsWith(".dll") || f.EndsWith(".json")))
            File.Copy(file, Path.Combine(alias, Path.GetFileName(file)));
        File.Copy(Path.Combine(AppContext.BaseDirectory, "PrimeSieve.Tests.exe"), Path.Combine(alias, "java.exe"));
        File.WriteAllText(Path.Combine(alias, "javac.exe"), "compiler placeholder");
        var oldHome = Environment.GetEnvironmentVariable("PRIMESIEVE_TEST_JAVA_HOME");
        Environment.SetEnvironmentVariable("PRIMESIEVE_TEST_JAVA_HOME", jdk);
        try
        {
            var java = Language.All.First(l => l.Id == "java");
            var resolved = await Toolchain.ResolveAsync(java, Path.Combine(alias, "javac.exe"), null);
            Check(resolved.Environment["JAVA_HOME"] == jdk && resolved.Helpers["java"] == Path.Combine(bin, "java.exe"), "Oracle-style executable shim resolves actual JDK instead of alias parent");
            var junction = Path.Combine(root, "linked javapath");
            await ProcessExecutor.RunAsync(cmd, ["/d", "/c", "mklink", "/J", junction, alias]);
            try
            {
                resolved = await Toolchain.ResolveAsync(java, Path.Combine(junction, "javac.exe"), null);
                Check(resolved.Environment["JAVA_HOME"] == jdk, "directory-linked JDK launcher resolves actual home");
            }
            finally { Directory.Delete(junction); }
        }
        finally { Environment.SetEnvironmentVariable("PRIMESIEVE_TEST_JAVA_HOME", oldHome); }
    }
    if (args.Contains("--integration"))
    {
        var discoveryContext = new QueuedContext();
        Task<RuntimeStatus[]> discovery;
        SynchronizationContext.SetSynchronizationContext(discoveryContext);
        try { discovery = RuntimeDiscovery.DiscoverAsync(); }
        finally { SynchronizationContext.SetSynchronizationContext(previousContext); }
        RuntimeStatus[] statuses;
        try { statuses = (await discovery.WaitAsync(TimeSpan.FromSeconds(120))).Where(s => s.Available).ToArray(); }
        finally { discoveryContext.Drain(); }
        Check(discoveryContext.PostCount == 0, "runtime discovery is independent of UI dispatch");
        var benchmarkContext = new QueuedContext();
        Task<BenchmarkSession> benchmark;
        SynchronizationContext.SetSynchronizationContext(benchmarkContext);
        try { benchmark = BenchmarkRunner.RunAsync(statuses.Take(1).ToArray(), new(10000, 2, 0, Mode: TimingMode.Startup)); }
        finally { SynchronizationContext.SetSynchronizationContext(previousContext); }
        try
        {
            var measured = await benchmark.WaitAsync(TimeSpan.FromSeconds(180));
            Check(measured.Results.Count == 1 && measured.Failures.Count == 0 && benchmarkContext.PostCount == 0, "startup benchmark completes with caller UI dispatch blocked");
        }
        finally { benchmarkContext.Drain(); }
        Check(statuses.Length >= 2, "multiple installed runtimes for cancellation test");
        using var cancel = new CancellationTokenSource();
        var progress = new InlineProgress(update => { if (update.Result != null) cancel.Cancel(); });
        var partial = await BenchmarkRunner.RunAsync(statuses, new(1000, 1, 0), progress: progress, cancellationToken: cancel.Token);
        Check(partial.Cancelled && !partial.Completed && partial.Results.Count == 0, "first-round cancellation excludes incomplete comparison");
        store.Save(partial);
        Check(store.Load().Sessions.Single().Cancelled && store.Load().Sessions.Single().Results.Count == 0, "cancelled session persists without partial-round ranks");
    }
    Console.WriteLine($"All {passed} regression checks passed."); return 0;
}
finally { Directory.Delete(root, true); }

internal sealed class InlineProgress(Action<BenchmarkEvent> update) : IProgress<BenchmarkEvent>
{
    public void Report(BenchmarkEvent value) => update(value);
}

internal sealed class QueuedContext : SynchronizationContext
{
    private readonly System.Collections.Concurrent.ConcurrentQueue<(SendOrPostCallback Callback, object? State)> pending = new();
    private int postCount;
    public int PostCount => postCount;
    public override void Post(SendOrPostCallback d, object? state) { Interlocked.Increment(ref postCount); pending.Enqueue((d, state)); }
    public void Drain() { while (pending.TryDequeue(out var item)) ThreadPool.QueueUserWorkItem(_ => item.Callback(item.State)); }
}
