using System.Text.Json;
using System.Text.Json.Serialization;
namespace PrimeSieve.Core;

public sealed record SieveImplementation(string Id, string LanguageID, string Name, string Source, string Variant,
    string Algorithm, int? Bits, string Storage, string Dependencies, string Allocation, string ThreadModel,
    string[] Architectures, string Explanation, int ProtocolVersion, string Provenance)
{
    [JsonIgnore] public bool IsBaseline => ProtocolVersion == 1;
    [JsonIgnore] public bool SupportsThroughput => ProtocolVersion >= 3;
    [JsonIgnore] public Language Language => Language.All.First(l => l.Id == LanguageID);
    [JsonIgnore] public string DisplayName => $"{Language.Name} · {Name}";
    [JsonIgnore] public string Summary => $"{Algorithm} · {Storage} · {ThreadModel} · {Dependencies}";
    public string[] Files() => IsBaseline ? WorkerSources.Names(Language) : LanguageID switch
    {
        "assembly" => [Source, "tuned_x86_64.s"], "r" => [Source, "clock.c"], _ => [Source]
    };
    private static readonly SieveImplementation[] Baselines = Language.All.Select(l => new SieveImplementation(l.Id, l.Id,
        l.Id == "assembly" ? "Assembly kernel with C harness · baseline" : "Baseline", l.Source, "baseline",
        "Odd-only Eratosthenes", l.Id is "lua" or "erlang" or "elixir" ? null : 8,
        l.Id is "lua" or "erlang" or "elixir" ? "Runtime container; flag size unknown" : "Byte flags",
        l.Id == "assembly" ? "C allocation/timing/output harness" : "No external sieve library",
        "Fresh candidate storage per pass", "Single sieve thread", ["arm64", "x86_64"],
        string.IsNullOrEmpty(l.Note) ? "Original common-loop implementation. Calculation includes result scanning." : l.Note,
        1, "PrimeSieve original baseline; exact source hash recorded")).ToArray();
    private static readonly Lazy<RegistrySnapshot> Registry = new(() => LoadRegistry(WorkerSources.PathFor("implementations.json")));
    public static SieveImplementation[] All => Registry.Value.Implementations;
    public static string? RegistryError => Registry.Value.Error;
    public static void ValidateRegistry()
    {
        if (RegistryError is {} error) throw new InvalidDataException(error);
    }
    internal sealed record RegistrySnapshot(SieveImplementation[] Implementations, string? Error);
    internal static RegistrySnapshot LoadRegistry(string path)
    {
        try
        {
            var options = new JsonSerializerOptions(JsonDefaults.Options)
            { RespectRequiredConstructorParameters = true, RespectNullableAnnotations = true };
            var variants = JsonSerializer.Deserialize<SieveImplementation[]>(File.ReadAllText(path), options);
            var languageIDs = Language.All.Select(l => l.Id).ToHashSet(StringComparer.Ordinal);
            if (variants == null || variants.Length == 0 || variants.Any(i => i == null ||
                string.IsNullOrWhiteSpace(i.Id) || string.IsNullOrWhiteSpace(i.Source) ||
                !languageIDs.Contains(i.LanguageID) || i.IsBaseline) ||
                Baselines.Concat(variants).Select(i => i.Id).Distinct(StringComparer.Ordinal).Count() != Baselines.Length + variants.Length)
                throw new InvalidDataException("Expected nonempty variants with unique IDs and known languages.");
            return new(Baselines.Concat(variants).ToArray(), null);
        }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or JsonException)
        {
            // UI descriptions and runtime discovery remain available; the runner refuses an incomplete registry.
            return new(Baselines, $"Unable to load implementation registry ({Path.GetFileName(path)}): {error.Message}");
        }
    }
    public static SieveImplementation[] Selected(string languageID, BenchmarkConfiguration config) => All.Where(i =>
        i.LanguageID == languageID && (config.ImplementationIDs != null ? config.ImplementationIDs.Contains(i.Id) : config.Implementations switch
        { ImplementationSelection.Baseline => i.IsBaseline, ImplementationSelection.Candidates => !i.IsBaseline, _ => true })).ToArray();
}
