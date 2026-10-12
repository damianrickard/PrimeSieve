using System.Globalization;
using System.Text;
using System.Text.Json;

namespace PrimeSieve.Core;

public sealed class SessionStore(string? root = null)
{
    public string Root { get; } = root ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PrimeSieve");
    private string SessionDirectory => Path.Combine(Root, "Sessions");
    public void Save(BenchmarkSession session) => AtomicWrite(Path.Combine(SessionDirectory, session.Id + ".json"), JsonSerializer.Serialize(session, JsonDefaults.Options));
    public (List<BenchmarkSession> Sessions, List<string> Errors) Load()
    {
        var sessions = new List<BenchmarkSession>(); var errors = new List<string>();
        if (!Directory.Exists(SessionDirectory)) return (sessions, errors);
        foreach (var path in Directory.EnumerateFiles(SessionDirectory, "*.json"))
        {
            if (!Guid.TryParse(Path.GetFileNameWithoutExtension(path), out _)) continue;
            try
            {
                var text = File.ReadAllText(path);
                var session = JsonSerializer.Deserialize<BenchmarkSession>(text, JsonDefaults.Options)
                    ?? throw new InvalidDataException("Empty session.");
                using var document = JsonDocument.Parse(text);
                if (!document.RootElement.TryGetProperty("configuration", out var configuration) || configuration.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Missing configuration.");
                if (!configuration.TryGetProperty("contractVersion", out _))
                    session.Configuration = session.Configuration with { ContractVersion = 1 };
                session.Configuration.Validate();
                if (session.Results == null || session.Failures == null || session.Results.Any(r => r.Signature == null || (r.Windows?.Any(w => w.Passes <= 0 || !double.IsFinite(w.ElapsedNS) || w.ElapsedNS <= 0 || w.Threads <= 0) ?? false) || r.SamplesNS == null || r.SamplesNS.Length == 0 || r.SamplesNS.Any(v => !double.IsFinite(v) || v < 0)))
                    throw new InvalidDataException("Invalid saved measurements.");
                sessions.Add(session);
            }
            catch (Exception error) when (error is JsonException or IOException or ArgumentException or InvalidDataException or NullReferenceException)
            { errors.Add(Path.GetFileName(path) + ": " + error.Message); }
        }
        return (sessions.OrderByDescending(s => s.Date).ToList(), errors);
    }
    public void Clear()
    {
        if (!Directory.Exists(SessionDirectory)) return;
        foreach (var file in Directory.EnumerateFiles(SessionDirectory, "*.json"))
            if (Guid.TryParse(Path.GetFileNameWithoutExtension(file), out _)) File.Delete(file);
    }
    public RuntimePreferences LoadRuntimePreferences()
    {
        var path = Path.Combine(Root, "runtimes.json");
        var warnings = new List<string>();
        try
        {
            // Missing is normal; unreadable or corrupt files remain untouched for recovery.
            if (!File.Exists(path) && !Directory.Exists(path)) return new([], warnings);
            var loaded = JsonSerializer.Deserialize<Dictionary<string, string?>>(File.ReadAllText(path), JsonDefaults.Options);
            if (loaded == null) throw new JsonException("Expected an object of runtime paths.");
            var valid = new Dictionary<string, string>();
            foreach (var (id, value) in loaded)
            {
                if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
                {
                    warnings.Add($"Ignored invalid runtime path for {id}; automatic detection will be used.");
                    continue;
                }
                valid[id] = value; // Keep missing explicit paths: discovery must not silently replace them.
            }
            return new(valid, warnings);
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
        {
            warnings.Add($"Runtime settings could not be read: {error.Message} Automatic detection will be used; the original file was kept.");
            return new([], warnings);
        }
    }
    public void SaveOverrides(IReadOnlyDictionary<string, string> paths) => AtomicWrite(Path.Combine(Root, "runtimes.json"), JsonSerializer.Serialize(paths, JsonDefaults.Options));
    public static void ExportJson(BenchmarkSession session, string path) => AtomicWrite(path, JsonSerializer.Serialize(session, JsonDefaults.Options));
    public static void ExportCsv(BenchmarkSession session, string path)
    {
        // Quote all fields and neutralize spreadsheet formula prefixes in machine/tool metadata.
        static string Cell(string text)
        {
            if (text.TrimStart().FirstOrDefault() is '=' or '+' or '-' or '@') text = "'" + text;
            return "\"" + text.Replace("\"", "\"\"") + "\"";
        }
        static string Number(double value) => value.ToString("R", CultureInfo.InvariantCulture);
        var csv = new StringBuilder("language,prime_count,mode,iterations,warmups,median_ns,mean_ns,min_ns,max_ns,samples_ns,last_prime,checksum,compilation_seconds,runtime,executable,source_sha256,source_hash_format,source_files,build_command,launch_command,helper_tools,machine,session_id,date,completed,cancelled,implementation_id,implementation_name,workload,upper_limit,contract_version,contract,rounds,round_order,score,score_unit,iqr,windows,machine_details\r\n");
        foreach (var result in session.Results)
        {
            string[] values = [result.Language, result.Signature.Count.ToString(), session.Configuration.Mode.ToString(), result.Iterations.ToString(),
                (session.Configuration.Mode == TimingMode.Startup ? 0 : session.Configuration.Warmups).ToString(), Number(result.MedianNS), Number(result.MeanNS),
                Number(result.MinimumNS), Number(result.MaximumNS), string.Join(';', result.SamplesNS.Select(Number)), result.Signature.LastPrime.ToString(),
                result.Signature.Checksum.ToString(), Number(result.CompilationSeconds), result.RuntimeVersion, result.ExecutablePath, result.SourceHash,
                result.SourceHashFormat.ToString(), string.Join(';', result.SourceFiles), JsonSerializer.Serialize(result.Command), JsonSerializer.Serialize(result.LaunchCommand),
                JsonSerializer.Serialize(result.HelperTools), session.Machine, session.Id.ToString(), session.Date.ToString("O"), session.Completed.ToString(), session.Cancelled.ToString(), result.Id, result.Implementation?.Name ?? "Legacy implementation", session.Configuration.Workload.ToString(),
                session.Configuration.SieveLimit.ToString(), session.Configuration.ContractVersion.ToString(), result.Contract ?? "Legacy contract",
                session.Configuration.Rounds.ToString(), JsonSerializer.Serialize(result.RoundOrders), Number(result.Score), result.IsThroughput ? "passes/second" : "nanoseconds",
                Number(result.InterquartileRange), JsonSerializer.Serialize(result.Windows), JsonSerializer.Serialize(session.MachineDetails)];
            csv.AppendLine(string.Join(',', values.Select(Cell)));
        }
        AtomicWrite(path, csv.ToString());
    }
    private static void AtomicWrite(string path, string contents)
    {
        path = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, contents, new UTF8Encoding(false)); File.Move(temporary, path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}

public sealed record RuntimePreferences(Dictionary<string, string> Paths, List<string> Warnings);
