using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace PrimeSieve.Core;

public static class BenchmarkRunner
{
    private sealed record Worker(string Directory, PreparedWorker Prepared, Dictionary<string,string> Environment, BenchmarkResult Result);
    public static Task<BenchmarkSession> RunAsync(IReadOnlyList<RuntimeStatus> statuses, BenchmarkConfiguration configuration,
        IReadOnlyDictionary<string, string>? overrides = null, IProgress<BenchmarkEvent>? progress = null, CancellationToken cancellationToken = default)
    {
        var selected = statuses.ToArray();
        var paths = overrides == null ? null : new Dictionary<string, string>(overrides);
        return Task.Run(() => RunCoreAsync(selected, configuration, paths, progress, cancellationToken));
    }
    private static async Task<BenchmarkSession> RunCoreAsync(IReadOnlyList<RuntimeStatus> statuses, BenchmarkConfiguration config,
        IReadOnlyDictionary<string,string>? overrides, IProgress<BenchmarkEvent>? progress, CancellationToken token)
    {
        config = config with { ContractVersion = 3 };
        config.Validate();
        SieveImplementation.ValidateRegistry();
        if (statuses.Count == 0 || statuses.Any(s => !s.Available)) throw new ArgumentException("Select at least one available language.");
        var choices = statuses.SelectMany(s => SieveImplementation.Selected(s.Language.Id, config).Select(i => (Status:s, Implementation:i))).ToArray();
        if (choices.Length == 0) throw new ArgumentException("No implementations match the selected languages and filter.");
        if (config.ImplementationIDs != null && (config.ImplementationIDs.Length == 0 || config.ImplementationIDs.Except(choices.Select(c => c.Implementation.Id)).Any()))
            throw new ArgumentException("Unknown implementation or missing selected runtime.");
        var session = new BenchmarkSession { Configuration = config, MachineDetails = MachineDetails.Capture() };
        var workers = new List<Worker>();
        try
        {
            progress?.Report(new("Preparing independent reference…", 0, choices.Length));
            var reference = PrimeReference.Calculate(config, token);
            var sequence = config.SieveLimit <= 100_000 ? PrimeReference.Sequence(reference.Count, config.SieveLimit) : null;
            for (var index = 0; index < choices.Length; index++)
            {
                token.ThrowIfCancellationRequested();
                var (status, implementation) = choices[index];
                progress?.Report(new($"Preparing {implementation.DisplayName}…", index, choices.Length));
                try
                {
                    if (config.Mode == TimingMode.Throughput && !implementation.SupportsThroughput)
                        throw new ArgumentException("This baseline has no duration harness. Choose a tuned variant for sieve throughput.");
                    workers.Add(await PrepareAsync(status, implementation, config, reference, overrides, token));
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception error) { session.Failures[implementation.Id] = error.Message; progress?.Report(new(error.Message, index + 1, choices.Length)); }
            }
            for (var round = 0; round < config.Rounds; round++)
            {
                var order = Enumerable.Range(0,workers.Count).Where(i => !session.Failures.ContainsKey(workers[i].Result.Id)).ToArray();
                Random.Shared.Shuffle(order); session.ExecutionOrder.Add(order.Select(i => workers[i].Result.Id).ToArray());
                foreach (var index in order)
                {
                    token.ThrowIfCancellationRequested();
                    var worker = workers[index]; var implementation = worker.Result.Implementation!;
                    progress?.Report(new($"Measuring {implementation.DisplayName} · round {round+1}/{config.Rounds}", round * choices.Length, config.Rounds * choices.Length));
                    try
                    {
                        string[] Arguments(int warm, int runs, bool fullSequence = false)
                        {
                            var args = worker.Prepared.Arguments.Concat(new[] { reference.Count.ToString(CultureInfo.InvariantCulture), config.SieveLimit.ToString(CultureInfo.InvariantCulture), warm.ToString(), runs.ToString() });
                            if (!implementation.IsBaseline) args = args.Concat(new[] { config.Mode == TimingMode.Throughput ? "throughput" : "calculation",
                                config.DurationSeconds.ToString(CultureInfo.InvariantCulture), config.Workload == Workload.FirstN ? "count" : "limit", implementation.Variant, sequence != null && (config.Mode != TimingMode.Startup || fullSequence) ? "1" : "0" });
                            return args.ToArray();
                        }
                        var samples = new List<WorkerSample>(); var elapsed = new List<double>();
                        if (config.Mode == TimingMode.Startup)
                        {
                            for (var run = 0; run < config.Repetitions; run++)
                            {
                                var output = await ProcessExecutor.RunAsync(worker.Prepared.Executable, Arguments(0,1), worker.Directory, config.TimeoutSeconds, token, worker.Environment);
                                samples.AddRange(Decode(output.Stdout,1,reference)); elapsed.Add(output.ElapsedNS);
                            }
                            // Keep complete-sequence construction and output outside startup wall-clock samples.
                            if (round == 0 && !implementation.IsBaseline && sequence != null)
                            {
                                var verification = await ProcessExecutor.RunAsync(worker.Prepared.Executable, Arguments(0,1,true), worker.Directory, config.TimeoutSeconds, token, worker.Environment);
                                Decode(verification.Stdout,1,reference,sequence);
                            }
                        }
                        else
                        {
                            var output = await ProcessExecutor.RunAsync(worker.Prepared.Executable, Arguments(config.Warmups,config.Repetitions),worker.Directory,config.TimeoutSeconds,token,worker.Environment, maxOutputCharacters: sequence != null && !implementation.IsBaseline ? 4_194_304 : 1_048_576);
                            samples.AddRange(Decode(output.Stdout,config.Repetitions,reference,implementation.IsBaseline ? null : sequence,
                                config.Mode == TimingMode.Throughput ? config.DurationSeconds : null)); elapsed.AddRange(samples.Select(s => s.ElapsedNS));
                        }
                        var result = worker.Result with { LaunchCommand = new[] {worker.Prepared.Executable}.Concat(Arguments(config.Mode == TimingMode.Startup ? 0 : config.Warmups,config.Mode == TimingMode.Startup ? 1 : config.Repetitions)).ToArray(), SamplesNS = worker.Result.SamplesNS.Concat(elapsed).ToArray(),
                            RoundOrders = (worker.Result.RoundOrders ?? []).Append(round+1).ToArray(),
                            Windows = config.Mode == TimingMode.Throughput ? (worker.Result.Windows ?? []).Concat(samples.Select(s => new MeasurementWindow(s.Passes!.Value,s.ElapsedNS))).ToArray() : null };
                        workers[index] = worker with { Result = result };
                        progress?.Report(new($"Verified {result.DisplayName} · round {round+1}", round * choices.Length + Array.IndexOf(order,index)+1, config.Rounds * choices.Length, result));
                    }
                    catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                    catch (Exception error) { session.Results.RemoveAll(r => r.Id == implementation.Id); session.Failures[implementation.Id] = error.Message; progress?.Report(new(error.Message,0,choices.Length,CompletedRoundResults:session.Results.ToArray())); }
                }
                token.ThrowIfCancellationRequested();
                session.Results.Clear();
                session.Results.AddRange(workers.Select(w => w.Result).Where(r => !session.Failures.ContainsKey(r.Id)));
                progress?.Report(new($"Completed round {round+1}", (round+1)*choices.Length, config.Rounds*choices.Length,
                    CompletedRoundResults: session.Results.ToArray()));
            }
            session.Completed = true;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { session.Cancelled = true; }
        finally { foreach (var worker in workers) Cleanup(worker.Directory); }
        session.Results.Sort(BenchmarkResult.Compare); return session;
    }
    private static async Task<Worker> PrepareAsync(RuntimeStatus status, SieveImplementation implementation, BenchmarkConfiguration config,
        PrimeSignature reference, IReadOnlyDictionary<string,string>? overrides, CancellationToken token)
    {
        var directory = Path.Combine(Path.GetTempPath(),"PrimeSieve-"+Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
        try
        {
            var names = implementation.Files().ToList();
            foreach (var name in names) File.Copy(WorkerSources.PathFor(name),Path.Combine(directory,name));
            var toolchain = await Toolchain.ResolveAsync(status.Language,status.Executable!,overrides,token);
            var helpers = await toolchain.RecordsAsync(token); var start = Stopwatch.GetTimestamp();
            var prepared = await WorkerBuilder.PrepareAsync(status.Language,status.Executable!,directory,toolchain,Math.Max(120,config.TimeoutSeconds),token,implementation);
            var compilation = prepared.Compiled ? Stopwatch.GetElapsedTime(start).TotalSeconds : 0;
            names.AddRange(prepared.GeneratedSources);
            var result = new BenchmarkResult(implementation.Id,status.Name,status.Version,status.Executable!,[],compilation,reference,
                prepared.BuildCommand,new[] { prepared.Executable }.Concat(prepared.Arguments).ToArray(),WorkerSources.Hash(names,directory),names.Order().ToArray(),helpers,
                Implementation:implementation, RoundOrders:[], Contract:config.MeasurementContract);
            return new(directory,prepared,toolchain.Environment,result);
        }
        catch { Cleanup(directory); throw; }
    }
    private static void Cleanup(string directory) { try { Directory.Delete(directory,true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
    public static WorkerSample[] Decode(string output, int expectedSamples, PrimeSignature reference, int[]? sequence = null, double? minimumWindowSeconds = null)
    {
        var samples = new List<WorkerSample>();
        foreach (var line in output.Split('\n').Select(s => s.Trim()).Where(s => s.StartsWith('{')))
        {
            using var document = JsonDocument.Parse(line); var e = document.RootElement;
            var sample = new WorkerSample(e.GetProperty("elapsed_ns").GetDouble(),e.GetProperty("count").GetInt32(),
                e.GetProperty("last_prime").GetInt32(),e.GetProperty("checksum").GetInt64(),
                e.TryGetProperty("passes",out var p) ? p.GetInt64() : null,
                e.TryGetProperty("primes",out var primes) ? primes.EnumerateArray().Select(x => x.GetInt32()).ToArray() : null);
            if (!double.IsFinite(sample.ElapsedNS) || sample.ElapsedNS < 0 || sample.Signature != reference)
                throw new InvalidDataException("Correctness verification failed. This result was excluded from the leaderboard.");
            if (sequence != null && (sample.Primes == null || !sequence.SequenceEqual(sample.Primes))) throw new InvalidDataException("Complete prime sequence verification failed.");
            if (minimumWindowSeconds is {} seconds && (sample.Passes is null or <= 0 || sample.ElapsedNS < seconds*1e9)) throw new InvalidDataException("Invalid throughput window: positive passes and the full requested duration are required.");
            samples.Add(sample);
        }
        if (samples.Count != expectedSamples) throw new InvalidDataException($"Expected {expectedSamples} measurements; received {samples.Count}.");
        return samples.ToArray();
    }
}
