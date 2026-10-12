using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PrimeSieve.Core;

public enum TimingMode { Calculation, Startup, Throughput }
public enum Workload { FirstN, UpperLimit }
public enum ImplementationSelection { Baseline, Candidates, All }

public sealed record BenchmarkConfiguration(int PrimeCount = 100_000, int Repetitions = 7,
    int Warmups = 3, double TimeoutSeconds = 120, TimingMode Mode = TimingMode.Calculation,
    Workload Workload = Workload.FirstN, int UpperLimit = 1_000_000, double DurationSeconds = 5,
    int Rounds = 1, ImplementationSelection Implementations = ImplementationSelection.Baseline,
    string[]? ImplementationIDs = null, int ContractVersion = 3)
{
    public int SieveLimit => Workload == Workload.UpperLimit ? UpperLimit : PrimeCount < 6 ? 15 : checked((int)Math.Ceiling(PrimeCount *
        (Math.Log(PrimeCount) + Math.Log(Math.Log(PrimeCount)))) + 16);

    public void Validate()
    {
        if (Workload == Workload.FirstN && PrimeCount is < 1 or > 10_000_000) throw new ArgumentException("Enter a prime count between 1 and 10,000,000.");
        if (Workload == Workload.UpperLimit && UpperLimit is < 2 or > 200_000_000) throw new ArgumentException("Enter an inclusive upper limit between 2 and 200,000,000.");
        if (Repetitions is < 1 or > 30 || Warmups is < 0 or > 20 || !double.IsFinite(TimeoutSeconds) || TimeoutSeconds is < 1 or > 3600)
            throw new ArgumentException("Iterations must be 1–30, warm-ups 0–20, and timeout 1–3,600 seconds.");
        if (Rounds is < 1 or > 10 || !double.IsFinite(DurationSeconds) || DurationSeconds is < 0.01 or > 60)
            throw new ArgumentException("Use 1–10 rounds and 0.01–60 seconds/window.");
        if (!Enum.IsDefined(Workload) || !Enum.IsDefined(Implementations)) throw new ArgumentException("Invalid workload or implementation selection.");
        if (Mode == TimingMode.Throughput && (Workload != Workload.UpperLimit || TimeoutSeconds <= DurationSeconds * Repetitions))
            throw new ArgumentException("Throughput requires an upper limit and a timeout longer than all windows in a round. Allow additional time for startup, warm-ups, final-pass overrun, verification and output.");
        if (!Enum.IsDefined(Mode)) throw new ArgumentException("Unknown timing mode.");
    }
    public double SuggestedThroughputTimeout => Math.Max(30, 2 * DurationSeconds * Repetitions);
    public string? TimeoutGuidance => Mode != TimingMode.Throughput ? null :
        $"The timeout covers the entire worker round: startup, warm-ups, measured windows, final-pass overrun, verification and output. Start with at least {SuggestedThroughputTimeout:G} seconds (twice the requested window time, with a 30-second minimum); slow runtimes or large limits may need more. This is a planning suggestion, not a completion guarantee.";
    public string WorkloadDescription => Workload == Workload.FirstN ? $"First {PrimeCount:N0} primes" : $"Primes ≤ {UpperLimit:N0}";
    public string MeasurementContract => Mode == TimingMode.Throughput
        ? "v3: fresh allocation + sieve + per-pass observation + prior-buffer release; retained final sieve verified after each wall-clock window; scan excluded"
        : $"v{ContractVersion}: allocation + initialization + sieve + result scan; checksum/output excluded from calculation; startup includes the entire worker";
}

public sealed record PrimeSignature(int Count, int LastPrime, long Checksum);
public sealed record WorkerSample(
    [property: JsonPropertyName("elapsed_ns")] double ElapsedNS,
    int Count, [property: JsonPropertyName("last_prime")] int LastPrime, long Checksum, long? Passes = null, int[]? Primes = null)
{
    [JsonIgnore] public PrimeSignature Signature => new(Count, LastPrime, Checksum);
}
public sealed record ToolRecord(string Role, string ExecutablePath, string Version);
public sealed record BenchmarkResult(string Id, string Language, string RuntimeVersion, string ExecutablePath,
    double[] SamplesNS, double CompilationSeconds, PrimeSignature Signature, string[] Command,
    string[] LaunchCommand, string SourceHash, string[] SourceFiles, ToolRecord[] HelperTools, int SourceHashFormat = 2,
    SieveImplementation? Implementation = null, MeasurementWindow[]? Windows = null, int[]? RoundOrders = null, string? Contract = null)
{
    public bool IsThroughput => Windows is { Length: > 0 };
    public string DisplayName => Implementation == null ? Language : $"{Language} · {Implementation.Name}";
    public double Score => IsThroughput ? Statistics.Median(Windows!.Select(w => w.PassesPerSecond)) : MedianNS;
    public string ScoreDisplay => IsThroughput ? $"{Score:F1} passes/s" : TimeDisplay.Format(Score);
    public string SpreadDisplay => IsThroughput ? $"{InterquartileRange:F1} passes/s" : TimeDisplay.Format(InterquartileRange);
    public double RankingCost => IsThroughput ? 1 / Score : Score;
    public double InterquartileRange => Statistics.Iqr(IsThroughput ? Windows!.Select(w => w.PassesPerSecond) : SamplesNS);
    public static int Compare(BenchmarkResult a, BenchmarkResult b) => a.IsThroughput ? b.Score.CompareTo(a.Score) : a.Score.CompareTo(b.Score);
    public double MeanNS => SamplesNS.Average();
    public double MedianNS { get { var a = SamplesNS.Order().ToArray(); return a.Length % 2 == 0 ? a[a.Length / 2 - 1] / 2 + a[a.Length / 2] / 2 : a[a.Length / 2]; } }
    public double MinimumNS => SamplesNS.Min();
    public double MaximumNS => SamplesNS.Max();
    public int Iterations => SamplesNS.Length;
    [JsonIgnore] public string MedianDisplay => TimeDisplay.Format(MedianNS);
    [JsonIgnore] public string MeanDisplay => TimeDisplay.Format(MeanNS);
    [JsonIgnore] public string RangeDisplay => $"{TimeDisplay.Format(MinimumNS)} – {TimeDisplay.Format(MaximumNS)}";
}
public sealed class BenchmarkSession
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public DateTimeOffset Date { get; init; } = DateTimeOffset.Now;
    public BenchmarkConfiguration Configuration { get; set; } = new();
    public string Machine { get; init; } = $"{Environment.MachineName} • {RuntimeInformation.OSDescription} • {RuntimeInformation.ProcessArchitecture}";
    public List<BenchmarkResult> Results { get; init; } = [];
    public Dictionary<string, string> Failures { get; init; } = [];
    public bool Completed { get; set; }
    public bool Cancelled { get; set; }
    public MachineDetails? MachineDetails { get; set; }
    public List<string[]> ExecutionOrder { get; set; } = [];
    [JsonIgnore] public string Summary => $"{Date:g}  •  {Configuration.WorkloadDescription}  •  {Results.Count} implementations • contract v{Configuration.ContractVersion}{(Cancelled ? " • cancelled" : "")}";
}
public sealed record BenchmarkEvent(string Message, int Finished, int Total, BenchmarkResult? Result = null,
    BenchmarkResult[]? CompletedRoundResults = null);
public static class JsonDefaults
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true,
        WriteIndented = true, Converters = { new JsonStringEnumConverter() }
    };
}
public static class TimeDisplay
{
    public static string Format(double ns) => ns switch
    {
        < 1000 => ns.ToString("F1", CultureInfo.InvariantCulture) + " ns",
        < 1_000_000 => (ns / 1000).ToString("F2", CultureInfo.InvariantCulture) + " µs",
        < 1_000_000_000 => (ns / 1_000_000).ToString("F2", CultureInfo.InvariantCulture) + " ms",
        _ => (ns / 1_000_000_000).ToString("F3", CultureInfo.InvariantCulture) + " s"
    };
}

public sealed record MeasurementWindow(long Passes, double ElapsedNS, int Threads = 1)
{
    public double PassesPerSecond => Passes * 1e9 / ElapsedNS;
    public double PassesPerSecondPerThread => PassesPerSecond / Threads;
}
public static class Statistics
{
    public static double Median(IEnumerable<double> a) => Quantile(a, 0.5);
    public static double Iqr(IEnumerable<double> a) => Quantile(a, 0.75) - Quantile(a, 0.25);
    public static double Quantile(IEnumerable<double> values, double q)
    {
        var a = values.Order().ToArray(); if (a.Length == 0) return 0;
        var p = (a.Length - 1) * q; var i = (int)p;
        return a[i] + (a[Math.Min(i + 1, a.Length - 1)] - a[i]) * (p - i);
    }
}
public sealed record MachineDetails(string CPU, int LogicalCores, string ExecutionArchitecture, string HardwareArchitecture, string Translation, string OperatingSystem)
{
    public static MachineDetails Capture()
    {
        var cpu = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "Unknown";
        if (System.OperatingSystem.IsWindows())
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\CentralProcessor\0");
            cpu = key?.GetValue("ProcessorNameString") as string ?? cpu;
        }
        return new(cpu.Trim(), Environment.ProcessorCount, RuntimeInformation.ProcessArchitecture.ToString(),
            RuntimeInformation.OSArchitecture.ToString(), RuntimeInformation.ProcessArchitecture == RuntimeInformation.OSArchitecture ? "Native host process; worker architecture not inspected" : "Translated host process; worker architecture not inspected", RuntimeInformation.OSDescription);
    }
}
