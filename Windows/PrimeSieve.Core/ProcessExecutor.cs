using System.Diagnostics;
using System.Text;

namespace PrimeSieve.Core;

public sealed record ProcessOutput(string Stdout, string Stderr, double ElapsedNS);
public static class ProcessExecutor
{
    public static Task<ProcessOutput> RunAsync(string executable, IEnumerable<string> arguments,
        string? directory = null, double timeoutSeconds = 120, CancellationToken cancellationToken = default,
        IReadOnlyDictionary<string, string>? environment = null, int maxOutputCharacters = 1_048_576)
    {
        if (maxOutputCharacters is < 1 or > 8_388_608) throw new ArgumentOutOfRangeException(nameof(maxOutputCharacters));
        var args = arguments.ToArray();
        var variables = environment == null ? null : new Dictionary<string, string>(environment);
        // Start the stopwatch and perform every process/I/O operation away from UI dispatch.
        return Task.Run(() => ExecuteAsync(executable, args, directory, timeoutSeconds, cancellationToken, variables, maxOutputCharacters));
    }

    private static async Task<ProcessOutput> ExecuteAsync(string executable, IEnumerable<string> arguments,
        string? directory = null, double timeoutSeconds = 120, CancellationToken cancellationToken = default,
        IReadOnlyDictionary<string, string>? environment = null, int maxOutputCharacters = 1_048_576)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var args = arguments.ToArray();
        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true,
            RedirectStandardError = true, RedirectStandardInput = true,
            WorkingDirectory = directory ?? Environment.CurrentDirectory
        };
        // Windows SDK wrappers (Kotlin, npm, etc.) are batch files. Reject expansion and
        // shell metacharacters rather than treating paths or arguments as shell code.
        if (OperatingSystem.IsWindows() && Path.GetExtension(executable).ToLowerInvariant() is ".cmd" or ".bat")
        {
            static string Quote(string value)
            {
                if (value.IndexOfAny(['"', '%', '!', '&', '|', '<', '>', '^', '\r', '\n']) >= 0)
                    throw new ArgumentException("Batch tool paths and arguments cannot contain shell metacharacters; use a direct executable or a simpler path.");
                return "\"" + value + "\"";
            }
            startInfo.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe");
            startInfo.Arguments = "/d /v:off /s /c \"" + string.Join(" ", new[] { executable }.Concat(args).Select(Quote)) + "\"";
        }
        else foreach (var arg in args) startInfo.ArgumentList.Add(arg);
        if (environment != null) foreach (var item in environment) startInfo.Environment[item.Key] = item.Value;
        startInfo.Environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1";
        startInfo.Environment["DOTNET_NOLOGO"] = "1";
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);
        var started = Stopwatch.GetTimestamp();
        using var worker = WorkerProcess.Start(startInfo);
        var process = worker.Process;
        // Anonymous pipe reads may be blocking underneath FileStream. Killing the contained
        // writers on cancellation unblocks them even after the immediate parent has exited.
        using var cancelWorker = linked.Token.Register(() =>
        {
            try { worker.Terminate(); }
            catch (System.ComponentModel.Win32Exception) { } // Cleanup below retries and surfaces failures.
        });
        // Cap each stream while continuing to drain it, avoiding unbounded compiler output.
        static async Task<(string Text, bool Truncated)> ReadAsync(StreamReader reader, CancellationToken token, int limit)
        {
            var text = new StringBuilder();
            var buffer = new char[4096];
            var truncated = false;
            int read;
            while ((read = await reader.ReadAsync(buffer.AsMemory(), token)) > 0)
            {
                var keep = Math.Min(read, Math.Max(0, limit - text.Length));
                text.Append(buffer, 0, keep);
                truncated |= keep < read;
            }
            return (text.ToString(), truncated);
        }
        var stdout = ReadAsync(worker.StandardOutput, linked.Token, maxOutputCharacters);
        var stderr = ReadAsync(worker.StandardError, linked.Token, 1_048_576);
        try
        {
            await process.WaitForExitAsync(linked.Token);
            var output = await stdout;
            var error = await stderr;
            var elapsed = Stopwatch.GetElapsedTime(started).TotalNanoseconds;
            if (output.Truncated || error.Truncated) throw new IOException("Worker output exceeded its configured capture limit.");
            if (process.ExitCode != 0) throw new IOException($"{Path.GetFileName(executable)} exited with code {process.ExitCode}: {(error.Text + "\n" + output.Text)[..Math.Min(3000, error.Text.Length + output.Text.Length + 1)]}");
            return new(output.Text, error.Text, elapsed);
        }
        catch
        {
            worker.Terminate();
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
            try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)); } catch (TimeoutException) { }
            try { await Task.WhenAll(stdout, stderr); } catch (OperationCanceledException) { }
            cancellationToken.ThrowIfCancellationRequested();
            if (timeout.IsCancellationRequested) throw new TimeoutException($"{Path.GetFileName(executable)} exceeded {timeoutSeconds:g} seconds.");
            throw;
        }

    }
}
