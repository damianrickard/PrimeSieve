using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace PrimeSieve.Core;

public static class BenchmarkRunner
{
    public static Task<BenchmarkSession> RunAsync(IReadOnlyList<RuntimeStatus> statuses, BenchmarkConfiguration configuration,
        IReadOnlyDictionary<string, string>? overrides = null, IProgress<BenchmarkEvent>? progress = null, CancellationToken cancellationToken = default)
    {
        var selected = statuses.ToArray();
        var paths = overrides == null ? null : new Dictionary<string, string>(overrides);
        // Always leave the caller's UI context, even when an awaited operation completes synchronously.
        // Do not pass cancellation to Task.Run: RunCoreAsync returns a persistable cancelled session.
        return Task.Run(() => RunCoreAsync(selected, configuration, paths, progress, cancellationToken));
    }

    private static async Task<BenchmarkSession> RunCoreAsync(IReadOnlyList<RuntimeStatus> statuses, BenchmarkConfiguration configuration,
        IReadOnlyDictionary<string, string>? overrides = null, IProgress<BenchmarkEvent>? progress = null, CancellationToken cancellationToken = default)
    {
        configuration.Validate();
        if (statuses.Count == 0 || statuses.Any(s => !s.Available)) throw new ArgumentException("Select at least one available language.");
        var session = new BenchmarkSession { Configuration = configuration };
        try
        {
            progress?.Report(new("Preparing independent reference…", 0, statuses.Count));
            var reference = await Task.Run(() => PrimeReference.Calculate(configuration.PrimeCount, configuration.SieveLimit, cancellationToken), cancellationToken);
            var order = statuses.ToArray(); Random.Shared.Shuffle(order);
            for (var index = 0; index < order.Length; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var status = order[index];
                progress?.Report(new($"Preparing {status.Name}…", index, order.Length));
                try
                {
                    var result = await RunWorkerAsync(status, configuration, reference, overrides, () =>
                        progress?.Report(new($"Measuring {status.Name}…", index, order.Length)), cancellationToken);
                    session.Results.Add(result);
                    progress?.Report(new($"Verified {status.Name}", index + 1, order.Length, result));
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (Exception error)
                {
                    session.Failures[status.Name] = error.Message;
                    progress?.Report(new($"{status.Name}: {error.Message}", index + 1, order.Length));
                }
            }
            session.Completed = true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { session.Cancelled = true; }
        session.Results.Sort((a, b) => a.MedianNS.CompareTo(b.MedianNS));
        return session;
    }

    private static async Task<BenchmarkResult> RunWorkerAsync(RuntimeStatus status, BenchmarkConfiguration config, PrimeSignature reference,
        IReadOnlyDictionary<string, string>? overrides, Action measuring, CancellationToken token)
    {
        var directory = Path.Combine(Path.GetTempPath(), "PrimeSieve-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var names = WorkerSources.Names(status.Language).ToList();
            foreach (var name in names) File.Copy(WorkerSources.PathFor(name), Path.Combine(directory, name));
            var toolchain = await Toolchain.ResolveAsync(status.Language, status.Executable!, overrides, token);
            var helpers = await toolchain.RecordsAsync(token);
            var start = Stopwatch.GetTimestamp();
            var worker = await WorkerBuilder.PrepareAsync(status.Language, status.Executable!, directory, toolchain, Math.Max(120, config.TimeoutSeconds), token);
            var compilation = worker.Compiled ? Stopwatch.GetElapsedTime(start).TotalSeconds : 0;
            names.AddRange(worker.GeneratedSources);
            var hash = WorkerSources.Hash(names, directory);
            measuring();
            string[] common = [config.PrimeCount.ToString(CultureInfo.InvariantCulture), config.SieveLimit.ToString(CultureInfo.InvariantCulture)];
            var samples = new List<double>();
            if (config.Mode == TimingMode.Calculation)
            {
                var output = await ProcessExecutor.RunAsync(worker.Executable, worker.Arguments.Concat(common).Concat([config.Warmups.ToString(), config.Repetitions.ToString()]), directory, config.TimeoutSeconds, token, toolchain.Environment);
                samples.AddRange(Decode(output.Stdout, config.Repetitions, reference).Select(s => s.ElapsedNS));
            }
            else
            {
                for (var run = 0; run < config.Repetitions; run++)
                {
                    var output = await ProcessExecutor.RunAsync(worker.Executable, worker.Arguments.Concat(common).Concat(["0", "1"]), directory, config.TimeoutSeconds, token, toolchain.Environment);
                    _ = Decode(output.Stdout, 1, reference);
                    samples.Add(output.ElapsedNS);
                }
            }
            return new(status.Language.Id, status.Name, status.Version, status.Executable!, samples.ToArray(), compilation,
                reference, worker.BuildCommand, new[] { worker.Executable }.Concat(worker.Arguments).ToArray(), hash, names.Order().ToArray(), helpers);
        }
        finally
        {
            // A failure to clean a transient compiler file must not discard verified measurements.
            try { Directory.Delete(directory, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    public static WorkerSample[] Decode(string output, int expectedSamples, PrimeSignature reference)
    {
        var samples = new List<WorkerSample>();
        foreach (var line in output.Split('\n').Select(s => s.Trim()).Where(s => s.StartsWith('{')))
        {
            using var document = JsonDocument.Parse(line);
            var element = document.RootElement;
            // Require each field; missing zero-valued fields must not deserialize as valid defaults.
            var sample = new WorkerSample(element.GetProperty("elapsed_ns").GetDouble(), element.GetProperty("count").GetInt32(),
                element.GetProperty("last_prime").GetInt32(), element.GetProperty("checksum").GetInt64());
            if (!double.IsFinite(sample.ElapsedNS) || sample.ElapsedNS < 0 || sample.Signature != reference)
                throw new InvalidDataException("Correctness verification failed. This result was excluded from the leaderboard.");
            samples.Add(sample);
        }
        if (samples.Count != expectedSamples) throw new InvalidDataException($"Expected {expectedSamples} measurements; received {samples.Count}.");
        return samples.ToArray();
    }
}
