using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PrimeSieve.Core;

public enum TimingMode { Calculation, Startup }

public sealed record BenchmarkConfiguration(int PrimeCount = 100_000, int Repetitions = 7,
    int Warmups = 3, double TimeoutSeconds = 120, TimingMode Mode = TimingMode.Calculation)
{
    public int SieveLimit => PrimeCount < 6 ? 15 : checked((int)Math.Ceiling(PrimeCount *
        (Math.Log(PrimeCount) + Math.Log(Math.Log(PrimeCount)))) + 16);

    public void Validate()
    {
        if (PrimeCount is < 1 or > 10_000_000) throw new ArgumentException("Enter a prime count between 1 and 10,000,000.");
        if (Repetitions is < 1 or > 30 || Warmups is < 0 or > 20 || !double.IsFinite(TimeoutSeconds) || TimeoutSeconds is < 1 or > 3600)
            throw new ArgumentException("Iterations must be 1–30, warm-ups 0–20, and timeout 1–3,600 seconds.");
        if (!Enum.IsDefined(Mode)) throw new ArgumentException("Unknown timing mode.");
    }
}

public sealed record PrimeSignature(int Count, int LastPrime, long Checksum);
public sealed record WorkerSample(
    [property: JsonPropertyName("elapsed_ns")] double ElapsedNS,
    int Count, [property: JsonPropertyName("last_prime")] int LastPrime, long Checksum)
{
    [JsonIgnore] public PrimeSignature Signature => new(Count, LastPrime, Checksum);
}
public sealed record ToolRecord(string Role, string ExecutablePath, string Version);
public sealed record BenchmarkResult(string Id, string Language, string RuntimeVersion, string ExecutablePath,
    double[] SamplesNS, double CompilationSeconds, PrimeSignature Signature, string[] Command,
    string[] LaunchCommand, string SourceHash, string[] SourceFiles, ToolRecord[] HelperTools, int SourceHashFormat = 2)
{
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
    public BenchmarkConfiguration Configuration { get; init; } = new();
    public string Machine { get; init; } = $"{Environment.MachineName} • {RuntimeInformation.OSDescription} • {RuntimeInformation.ProcessArchitecture}";
    public List<BenchmarkResult> Results { get; init; } = [];
    public Dictionary<string, string> Failures { get; init; } = [];
    public bool Completed { get; set; }
    public bool Cancelled { get; set; }
    [JsonIgnore] public string Summary => $"{Date:g}  •  {Configuration.PrimeCount:N0} primes  •  {Results.Count} languages{(Cancelled ? " • cancelled" : "")}";
}
public sealed record BenchmarkEvent(string Message, int Finished, int Total, BenchmarkResult? Result = null);
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
