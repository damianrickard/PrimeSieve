namespace PrimeSieve.Core;

public sealed record PreparedWorker(string Executable, string[] Arguments, string[] BuildCommand, bool Compiled, string[] GeneratedSources);
public static class WorkerBuilder
{
    public static async Task<PreparedWorker> PrepareAsync(Language language, string tool, string directory,
        Toolchain toolchain, double timeout, CancellationToken token, SieveImplementation? implementation = null)
    {
        var source = implementation?.Source ?? language.Source;
        var binary = Path.Combine(directory, OperatingSystem.IsWindows() ? "worker.exe" : "worker");
        async Task Build(string[] args, string? compiler = null) =>
            _ = await ProcessExecutor.RunAsync(compiler ?? tool, args, directory, timeout, token, toolchain.Environment);
        async Task<PreparedWorker> Native(params string[] args)
        {
            await Build(args); return new(binary, [], new[] { tool }.Concat(args).ToArray(), true, []);
        }
        PreparedWorker Script(params string[] args) => new(tool, args, new[] { tool }.Concat(args).ToArray(), false, []);
        switch (language.Id)
        {
            case "c": return await Native("-O3", "-std=c11", source, "-o", binary);
            case "cpp": return await Native("-O3", "-std=c++17", source, "-o", binary);
            case "assembly": return await Native("-O3", source, implementation is { IsBaseline: false } ? "tuned_x86_64.s" : "sieve_x86_64.s", "-o", binary);
            case "swift": return await Native("-O", source, "-o", binary);
            case "rust": return await Native("-C", "opt-level=3", source, "-o", binary);
            case "go": return await Native("build", "-o", binary, source);
            case "zig": return await Native(OperatingSystem.IsWindows()
                ? ["build-exe", source, "clock.c", "-O", "ReleaseFast", "-lc", "-femit-bin=" + binary]
                : ["build-exe", source, "-O", "ReleaseFast", "-lc", "-femit-bin=" + binary]);
            case "d": return await Native("-O3", "-release", source, "-of=" + binary);
            case "fortran": return await Native("-O3", source, "-o", binary);
            case "nim": return await Native("c", "-d:release", "--out:" + binary, source);
            case "haskell": return await Native("-O2", source, "-o", binary);
            case "ocaml": return await Native("-O3", "clock_stubs.c", source, "-o", binary);
            case "crystal": return await Native("build", "--release", source, "-o", binary);
            case "pascal": return await Native("-O3", "-o" + binary, source);
            case "csharp":
            case "fsharp":
            {
                var version = await ProcessExecutor.RunAsync(tool, ["--version"], directory, 15, token);
                if (!int.TryParse(version.Stdout.Trim().Split('.')[0], out var major) || major < 6)
                    throw new InvalidOperationException("A .NET SDK 6 or newer is required.");
                var project = "Worker." + (language.Id == "csharp" ? "csproj" : "fsproj");
                // Isolate build property and target imports from unrelated temporary-directory files.
                await File.WriteAllTextAsync(Path.Combine(directory, "Directory.Build.props"), "<Project />", token);
                await File.WriteAllTextAsync(Path.Combine(directory, "Directory.Build.targets"), "<Project />", token);
                await File.WriteAllTextAsync(Path.Combine(directory, project), $"""
                    <Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net{major}.0</TargetFramework><EnableDefaultCompileItems>false</EnableDefaultCompileItems><InvariantGlobalization>true</InvariantGlobalization><NuGetAudit>false</NuGetAudit><RestoreIgnoreFailedSources>true</RestoreIgnoreFailedSources></PropertyGroup><ItemGroup><Compile Include="{source}" /></ItemGroup></Project>
                    """, token);
                string[] args = major >= 7 ? ["build", project, "-c", "Release", "-o", "out", "--nologo", "--disable-build-servers"]
                    : ["build", project, "-c", "Release", "-o", "out", "--nologo"];
                await Build(args);
                return new(tool, [Path.Combine(directory, "out", "Worker.dll")], new[] { tool }.Concat(args).ToArray(), true,
                    [project, "Directory.Build.props", "Directory.Build.targets"]);
            }
            case "java":
            {
                string[] args = [source, "-d", directory]; await Build(args);
                return new(toolchain.Helpers["java"], ["-cp", directory, "Sieve"], new[] { tool }.Concat(args).ToArray(), true, []);
            }
            case "kotlin":
            case "scala":
            {
                string[] args = language.Id == "kotlin" ? [source, "-include-runtime", "-d", "worker.jar"]
                    : ["--power", "package", source, "--assembly", "--server=false", "--java-home", toolchain.Environment["JAVA_HOME"], "-o", "worker.jar"];
                await Build(args);
                return new(toolchain.Helpers["java"], ["-jar", "worker.jar"], new[] { tool }.Concat(args).ToArray(), true, []);
            }
            case "groovy":
            {
                var folder = Path.GetDirectoryName(tool)!;
                var compiler = new[] { "groovyc.exe", "groovyc.bat", "groovyc.cmd", "groovyc" }.Select(n => Path.Combine(folder, n)).FirstOrDefault(File.Exists)
                    ?? throw new FileNotFoundException("groovyc must be next to the selected Groovy.");
                var libraries = Path.Combine(Path.GetDirectoryName(folder)!, "lib");
                if (!Directory.Exists(libraries)) throw new DirectoryNotFoundException("Groovy's lib folder was not found.");
                string[] args = ["-d", directory, source]; await Build(args, compiler);
                return new(toolchain.Helpers["java"], ["-cp", directory + Path.PathSeparator + Path.Combine(libraries, "*"), "Sieve"],
                    new[] { compiler }.Concat(args).ToArray(), true, []);
            }
            case "typescript":
            {
                // Use the selected Node explicitly, including when npm's tsc is a .cmd wrapper.
                var tsc = new[] { Path.Combine(Path.GetDirectoryName(tool)!, "node_modules", "typescript", "bin", "tsc"),
                    Path.Combine(Path.GetDirectoryName(tool)!, "..", "lib", "node_modules", "typescript", "bin", "tsc") }.FirstOrDefault(File.Exists);
                if (tsc == null) throw new FileNotFoundException("Cannot find TypeScript's bin/tsc beside the selected npm wrapper.");
                string[] args = [tsc, source, "--target", "ES2020", "--module", "commonjs", "--outDir", "out"];
                await Build(args, toolchain.Helpers["node"]);
                return new(toolchain.Helpers["node"], ["out/sieve.js"], new[] { toolchain.Helpers["node"] }.Concat(args).ToArray(), true, []);
            }
            case "lua":
            case "r":
            case "lisp":
            {
                var compiler = toolchain.Helpers["clock compiler"];
                var args = new List<string> { "-O2", OperatingSystem.IsWindows() ? "-shared" : "-dynamiclib", "clock.c", "-o", OperatingSystem.IsWindows() ? "clock.dll" : "clock.dylib" };
                if (language.Id == "lua") args.AddRange(OperatingSystem.IsWindows() ? ["-DLUA_CLOCK", "-lpsapi"] : ["-DLUA_CLOCK", "-undefined", "dynamic_lookup"]);
                await Build(args.ToArray(), compiler);
                return new(tool, language.Id == "lisp" ? ["--script", source] : [source], new[] { compiler }.Concat(args).ToArray(), true, []);
            }
            case "clojure": return Script("-M", source);
            case "python": return Script("-B", source);
            case "julia": return Script("--startup-file=no", "--threads=1", source);
            case "scheme":
            {
                string[] args = ["--no-auto-compile", "-c", "(compile-file \"sieve.scm\" #:output-file \"worker.go\")"];
                await Build(args);
                return new(tool, ["--no-auto-compile", "-c", "(load-compiled \"worker.go\")"], new[] { tool }.Concat(args).ToArray(), true, []);
            }
            default: return Script(source);
        }
    }
}
