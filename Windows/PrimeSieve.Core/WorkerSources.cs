using System.Security.Cryptography;
using System.Text;

namespace PrimeSieve.Core;

public sealed record CodeSection(string Title, int SourceLine, string Code);
public static class WorkerSources
{
    public static string PathFor(string name)
    {
        var windows = Path.Combine(AppContext.BaseDirectory, "WindowsWorkers", name);
        return OperatingSystem.IsWindows() && File.Exists(windows) ? windows : Path.Combine(AppContext.BaseDirectory, "Workers", name);
    }
    public static string[] Names(Language language) => language.Id switch
    {
        "assembly" => [language.Source, "sieve_x86_64.s"],
        "lua" or "r" or "lisp" => [language.Source, "clock.c"],
        "zig" when OperatingSystem.IsWindows() => [language.Source, "clock.c"],
        "ocaml" => [language.Source, "clock_stubs.c"],
        _ => [language.Source]
    };
    public static string Hash(IEnumerable<string> names, string directory)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData(Encoding.UTF8.GetBytes("PrimeSieve source manifest v2\n"));
        foreach (var name in names.Order(StringComparer.Ordinal))
        foreach (var bytes in new[] { Encoding.UTF8.GetBytes(name), File.ReadAllBytes(Path.Combine(directory, name)) })
        {
            hash.AppendData(Encoding.UTF8.GetBytes(bytes.Length + ":"));
            hash.AppendData(bytes);
        }
        return Convert.ToHexStringLower(hash.GetHashAndReset());
    }
    public static CodeSection[] Sections(SieveImplementation implementation) => implementation.IsBaseline ? Sections(implementation.Language)
        : Parse(File.ReadAllText(PathFor(implementation.LanguageID == "assembly" ? "tuned_x86_64.s" : implementation.Source)));
    public static CodeSection[] Sections(Language language) => Parse(File.ReadAllText(PathFor(language.Id == "assembly" ? "sieve_x86_64.s" : language.Source)));
    public static CodeSection[] Parse(string source)
    {
        var sections = new List<CodeSection>();
        string? title = null;
        var content = new List<string>();
        var first = 0;
        var lines = source.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var line = lines[i];
            var marker = line.IndexOf("PRIME-BEGIN: ", StringComparison.Ordinal);
            if (marker >= 0)
            {
                if (title != null) throw new InvalidDataException("Nested code-explorer markers.");
                title = line[(marker + 13)..].Replace(" *)", "").Trim(); first = i + 2; content.Clear();
            }
            else if (line.Contains("PRIME-END", StringComparison.Ordinal))
            {
                if (title == null || content.Count == 0) throw new InvalidDataException("Incomplete code-explorer section.");
                var indent = content.Where(s => !string.IsNullOrWhiteSpace(s)).Select(s => s.TakeWhile(c => c == ' ').Count()).DefaultIfEmpty(0).Min();
                sections.Add(new(title, first, string.Join('\n', content.Select(s => s[Math.Min(indent, s.Length)..])))); title = null;
            }
            else if (title != null) content.Add(line);
        }
        if (title != null || sections.Count == 0) throw new InvalidDataException("Documented calculation code is unavailable.");
        return sections.ToArray();
    }
}
