using System.Runtime.InteropServices;

namespace PrimeSieve.Core;

public static class RuntimeDiscovery
{
    public static IEnumerable<string> SearchPaths()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).ToList();
        paths.AddRange([Path.Combine(programFiles, "dotnet"), Path.Combine(programFiles, "nodejs"),
            Path.Combine(programFiles, "LLVM", "bin"), Path.Combine(home, ".cargo", "bin"),
            Path.Combine(home, "go", "bin"), Path.Combine(programFiles, "Go", "bin"),
            Path.Combine(home, "scoop", "shims"), Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm"),
            @"C:\msys64\ucrt64\bin", @"C:\msys64\mingw64\bin"]);
        foreach (var parent in new[] { programFiles, Path.Combine(programFiles, "Java"), Path.Combine(programFiles, "Eclipse Adoptium"),
                     Path.Combine(local, "Programs", "Python"), Path.Combine(local, "Programs"), Path.Combine(programFiles, "R") })
        {
            if (!Directory.Exists(parent)) continue;
            try
            {
                foreach (var folder in Directory.GetDirectories(parent))
                {
                    paths.Add(Path.Combine(folder, "bin"));
                    if (Path.GetFileName(folder).StartsWith("Python", StringComparison.OrdinalIgnoreCase)) paths.Add(folder);
                }
            }
            catch (UnauthorizedAccessException) { }
        }
        return paths.Select(p => p.Trim().Trim('"')).Where(p => p.Length > 0 &&
            !p.Contains("Microsoft\\WindowsApps", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase);
    }

    public static string? Find(IEnumerable<string> names, IReadOnlyDictionary<string, string>? overrides = null, string? id = null)
    {
        if (id != null && overrides != null && overrides.TryGetValue(id, out var selected))
            return !string.IsNullOrWhiteSpace(selected) && Path.IsPathFullyQualified(selected) && File.Exists(selected) ? selected : null;
        foreach (var name in names)
        foreach (var folder in SearchPaths())
        foreach (var extension in OperatingSystem.IsWindows() ? new[] { ".exe", ".cmd", ".bat", "" } : new[] { "" })
        {
            var path = Path.Combine(folder, name + extension);
            if (File.Exists(path)) return path;
        }
        return null;
    }

    public static Task<RuntimeStatus[]> DiscoverAsync(IReadOnlyDictionary<string, string>? overrides = null,
        CancellationToken cancellationToken = default)
    {
        var paths = overrides == null ? null : new Dictionary<string, string>(overrides);
        return Task.Run(() => DiscoverCoreAsync(paths, cancellationToken));
    }

    private static async Task<RuntimeStatus[]> DiscoverCoreAsync(IReadOnlyDictionary<string, string>? overrides = null,
        CancellationToken cancellationToken = default)
    {
        var statuses = new List<RuntimeStatus>();
        foreach (var language in Language.All)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (language.Id == "assembly" && RuntimeInformation.ProcessArchitecture != Architecture.X64)
            {
                statuses.Add(new(language, null, "Windows assembly requires x64.")); continue;
            }
            var executable = Find(language.Executables, overrides, language.Id);
            if (executable == null)
            {
                statuses.Add(new(language, null, overrides?.ContainsKey(language.Id) == true ? "Selected executable is missing." : "Not installed")); continue;
            }
            try
            {
                var toolchain = await Toolchain.ResolveAsync(language, executable, overrides, cancellationToken);
                var probe = executable;
                string[] args = [language.VersionArgument];
                if (language.Id == "erlang")
                {
                    probe = Path.Combine(Path.GetDirectoryName(executable)!, OperatingSystem.IsWindows() ? "erl.exe" : "erl");
                    args = ["-noshell", "-eval", "io:format(\"OTP ~s~n\", [erlang:system_info(otp_release)]), halt()."];
                }
                var output = await ProcessExecutor.RunAsync(probe, args, timeoutSeconds: 15, cancellationToken: cancellationToken, environment: toolchain.Environment);
                var version = (output.Stdout + "\n" + output.Stderr).Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim() ?? language.Runtime;
                if (language.Id is "csharp" or "fsharp" && (!int.TryParse(version.Split('.')[0], out var major) || major < 6))
                    throw new InvalidOperationException("A .NET SDK version 6 or newer is required.");
                statuses.Add(new(language, executable, version));
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception error) { statuses.Add(new(language, null, "Runtime check failed: " + error.Message)); }
        }
        return statuses.ToArray();
    }
}

public sealed class Toolchain
{
    public Dictionary<string, string> Helpers { get; } = [];
    public Dictionary<string, string> Environment { get; } = [];
    public static async Task<Toolchain> ResolveAsync(Language language, string primary, IReadOnlyDictionary<string, string>? overrides, CancellationToken token = default)
    {
        var result = new Toolchain();
        string Require(string id, params string[] names) => RuntimeDiscovery.Find(names, overrides, id)
            ?? throw new InvalidOperationException($"Select or install {string.Join(" or ", names)} for {language.Name}.");
        if (language.Family == "JVM")
        {
            var javac = language.Id == "java" ? primary : Require("java", "javac");
            var javaName = OperatingSystem.IsWindows() ? "java.exe" : "java";
            var java = Path.Combine(Path.GetDirectoryName(javac)!, javaName);
            if (!File.Exists(java))
            {
                var target = new FileInfo(javac).ResolveLinkTarget(returnFinalTarget: true);
                if (target != null) java = Path.Combine(Path.GetDirectoryName(target.FullName)!, javaName);
            }
            if (!File.Exists(java)) throw new FileNotFoundException("java must be next to the selected javac or its link target.");
            // Ask the selected JVM: Oracle javapath may contain executable shims as well as
            // file/directory links, so following just the javac file link is insufficient.
            var properties = await ProcessExecutor.RunAsync(java, ["-XshowSettings:properties", "-version"],
                timeoutSeconds: 15, cancellationToken: token).ConfigureAwait(false);
            var home = JavaHomeFromProperties(properties.Stdout + "\n" + properties.Stderr);
            java = Path.Combine(home, "bin", javaName);
            result.Helpers["java"] = java;
            result.Environment["JAVA_HOME"] = home;
            result.Environment["JAVA_CMD"] = java;
            result.Environment["JAVACMD"] = java;
        }
        if (language.Id == "typescript") result.Helpers["node"] = Require("javascript", "node");
        if (language.Id is "lua" or "r" or "lisp") result.Helpers["clock compiler"] = Require("c", "clang", "gcc");
        result.Environment["PATH"] = string.Join(Path.PathSeparator, result.Helpers.Values.Select(p => Path.GetDirectoryName(p)!)
            .Concat([Path.GetDirectoryName(primary)!]).Concat(RuntimeDiscovery.SearchPaths()).Distinct(StringComparer.OrdinalIgnoreCase));
        return result;
    }
    public static string JavaHomeFromProperties(string output)
    {
        const string key = "java.home =";
        var value = output.Split('\n').Select(line => line.Trim()).FirstOrDefault(line => line.StartsWith(key, StringComparison.Ordinal));
        var home = value?[key.Length..].Trim();
        if (string.IsNullOrWhiteSpace(home) || !Path.IsPathFullyQualified(home))
            throw new InvalidDataException("The selected Java runtime did not report a valid java.home.");
        var suffix = OperatingSystem.IsWindows() ? ".exe" : "";
        static bool HasTools(string folder, string suffix) => File.Exists(Path.Combine(folder, "bin", "java" + suffix)) && File.Exists(Path.Combine(folder, "bin", "javac" + suffix));
        if (!HasTools(home, suffix) && Path.GetFileName(home).Equals("jre", StringComparison.OrdinalIgnoreCase))
            home = Path.GetDirectoryName(home) ?? home; // JDK 8 reports the nested JRE.
        if (!HasTools(home, suffix)) throw new InvalidDataException("The selected Java runtime must belong to a JDK with bin/java and bin/javac. Choose the JDK compiler in Language setup.");
        return Path.GetFullPath(home);
    }
    public async Task<ToolRecord[]> RecordsAsync(CancellationToken token)
    {
        var records = new List<ToolRecord>();
        foreach (var (role, path) in Helpers)
        {
            var output = await ProcessExecutor.RunAsync(path, [role == "java" ? "-version" : "--version"], timeoutSeconds: 15, cancellationToken: token, environment: Environment);
            records.Add(new(role, path, (output.Stdout + "\n" + output.Stderr).Split('\n', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim() ?? "Unknown"));
        }
        return records.ToArray();
    }
}
