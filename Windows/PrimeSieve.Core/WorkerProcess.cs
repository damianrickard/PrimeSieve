using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace PrimeSieve.Core;

// Windows creates the worker atomically in a kill-on-close job. It cannot spawn a child
// before containment. Only its three standard pipe handles are inherited (not the job).
internal sealed class WorkerProcess : IDisposable
{
    public Process Process { get; }
    public StreamReader StandardOutput { get; }
    public StreamReader StandardError { get; }
    private readonly WindowsJob? job;
    private WorkerProcess(Process process, StreamReader output, StreamReader error, WindowsJob? job = null)
    { Process = process; StandardOutput = output; StandardError = error; this.job = job; }

    public static WorkerProcess Start(ProcessStartInfo info)
    {
        if (OperatingSystem.IsWindows()) return StartWindows(info);
        var process = new Process { StartInfo = info };
        try
        {
            if (!process.Start()) throw new IOException("Unable to start worker.");
            process.StandardInput.Close();
            return new(process, process.StandardOutput, process.StandardError);
        }
        catch { process.Dispose(); throw; }
    }

    public void Terminate()
    {
        if (job != null) { job.Dispose(); return; }
        try { if (!Process.HasExited) Process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
    }
    public void Dispose()
    {
        job?.Dispose();
        StandardOutput.Dispose(); StandardError.Dispose(); Process.Dispose();
    }

    private static WorkerProcess StartWindows(ProcessStartInfo info)
    {
        var job = WindowsJob.Create();
        Process? process = null;
        StreamReader? output = null, error = null;
        var native = new ProcessInformation();
        try
        {
            using var stdout = new Pipe();
            using var stderr = new Pipe();
            using var stdin = new Pipe();
            stdout.MakeNonInheritable(stdout.Read);
            stderr.MakeNonInheritable(stderr.Read);
            stdin.MakeNonInheritable(stdin.Write);
            using var attributes = new ProcessAttributes(job.Handle, stdin.Read, stdout.Write, stderr.Write);
            var startup = new StartupInfoEx
            {
                Startup = new StartupInfo
                {
                    Size = Marshal.SizeOf<StartupInfoEx>(), Flags = 0x100, // STARTF_USESTDHANDLES
                    Input = stdin.Read.DangerousGetHandle(), Output = stdout.Write.DangerousGetHandle(), Error = stderr.Write.DangerousGetHandle()
                },
                Attributes = attributes.Pointer
            };
            var arguments = info.ArgumentList.Count > 0 ? string.Join(' ', info.ArgumentList.Select(QuoteArgument)) : info.Arguments;
            var command = new StringBuilder(QuoteArgument(info.FileName) + " " + arguments);
            var environment = string.Join('\0', info.Environment.Where(pair => pair.Value != null)
                .OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase).Select(pair => pair.Key + "=" + pair.Value)) + "\0\0";
            // JOB_LIST applies at creation. Suspension lets us open a managed process handle
            // before a fast executable exits; it is not used to defer assigning the job.
            const uint flags = 0x00080000 | 0x00000400 | 0x08000000 | 0x00000004;
            if (!CreateProcess(info.FileName, command, IntPtr.Zero, IntPtr.Zero, true, flags, environment,
                    info.WorkingDirectory, ref startup, out native)) throw new Win32Exception(Marshal.GetLastWin32Error());
            process = Process.GetProcessById(native.ProcessId);
            _ = process.Handle; // Hold a stable OS handle across exit / PID reuse.
            output = new StreamReader(new FileStream(stdout.TakeRead(), FileAccess.Read), info.StandardOutputEncoding ?? Console.OutputEncoding, true);
            error = new StreamReader(new FileStream(stderr.TakeRead(), FileAccess.Read), info.StandardErrorEncoding ?? Console.OutputEncoding, true);
            stdin.Write.Dispose(); // The child sees EOF immediately.
            stdout.Write.Dispose(); stderr.Write.Dispose(); stdin.Read.Dispose();
            if (ResumeThread(native.Thread) == uint.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
            return new(process, output, error, job);
        }
        catch
        {
            job.Dispose(); // Also kills a suspended process if setup fails.
            output?.Dispose(); error?.Dispose(); process?.Dispose();
            throw;
        }
        finally
        {
            if (native.Thread != IntPtr.Zero) CloseHandle(native.Thread);
            if (native.Process != IntPtr.Zero) CloseHandle(native.Process);
        }
    }

    // Microsoft C runtime command-line escaping. Batch commands already have separately
    // validated cmd.exe quoting in ProcessExecutor and use ProcessStartInfo.Arguments.
    private static string QuoteArgument(string argument)
    {
        if (argument.Length > 0 && !argument.Any(char.IsWhiteSpace) && !argument.Contains('"')) return argument;
        var quoted = new StringBuilder("\"");
        var slashes = 0;
        foreach (var character in argument)
        {
            if (character == '\\') { slashes++; continue; }
            quoted.Append('\\', character == '"' ? slashes * 2 + 1 : slashes);
            quoted.Append(character); slashes = 0;
        }
        return quoted.Append('\\', slashes * 2).Append('"').ToString();
    }

    private sealed class Pipe : IDisposable
    {
        public SafeFileHandle Read { get; private set; }
        public SafeFileHandle Write { get; }
        public Pipe()
        {
            var security = new SecurityAttributes { Size = Marshal.SizeOf<SecurityAttributes>(), InheritHandle = true };
            if (!CreatePipe(out var read, out var write, ref security, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
            Read = read; Write = write;
        }
        public void MakeNonInheritable(SafeFileHandle handle)
        {
            if (!SetHandleInformation(handle, 1, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        public SafeFileHandle TakeRead() { var handle = Read; Read = new SafeFileHandle(IntPtr.Zero, true); return handle; }
        public void Dispose() { Read.Dispose(); Write.Dispose(); }
    }

    private sealed class ProcessAttributes : IDisposable
    {
        public IntPtr Pointer { get; private set; }
        private IntPtr jobs, handles;
        private bool initialized;
        public ProcessAttributes(SafeFileHandle job, params SafeFileHandle[] inherited)
        {
            try
            {
                nuint size = 0;
                _ = InitializeProcThreadAttributeList(IntPtr.Zero, 2, 0, ref size);
                Pointer = Marshal.AllocHGlobal(checked((nint)size));
                if (!InitializeProcThreadAttributeList(Pointer, 2, 0, ref size)) throw new Win32Exception(Marshal.GetLastWin32Error());
                initialized = true;
                jobs = Marshal.AllocHGlobal(IntPtr.Size);
                Marshal.WriteIntPtr(jobs, job.DangerousGetHandle());
                handles = Marshal.AllocHGlobal(IntPtr.Size * inherited.Length);
                for (var i = 0; i < inherited.Length; i++) Marshal.WriteIntPtr(handles, i * IntPtr.Size, inherited[i].DangerousGetHandle());
                if (!UpdateProcThreadAttribute(Pointer, 0, 0x0002000D, jobs, (nuint)IntPtr.Size, IntPtr.Zero, IntPtr.Zero) ||
                    !UpdateProcThreadAttribute(Pointer, 0, 0x00020002, handles, (nuint)(IntPtr.Size * inherited.Length), IntPtr.Zero, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            if (initialized) { DeleteProcThreadAttributeList(Pointer); initialized = false; }
            Marshal.FreeHGlobal(Pointer); Marshal.FreeHGlobal(jobs); Marshal.FreeHGlobal(handles);
            Pointer = jobs = handles = IntPtr.Zero;
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SecurityAttributes { public int Size; public IntPtr Descriptor; [MarshalAs(UnmanagedType.Bool)] public bool InheritHandle; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int Size; public string? Reserved, Desktop, Title;
        public uint X, Y, XSize, YSize, XCountChars, YCountChars, FillAttribute, Flags;
        public ushort ShowWindow, ReservedSize; public IntPtr ReservedData, Input, Output, Error;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct StartupInfoEx { public StartupInfo Startup; public IntPtr Attributes; }
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation { public IntPtr Process, Thread; public int ProcessId, ThreadId; }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreatePipe(out SafeFileHandle read, out SafeFileHandle write, ref SecurityAttributes attributes, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetHandleInformation(SafeFileHandle handle, uint mask, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool InitializeProcThreadAttributeList(IntPtr attributes, int count, int flags, ref nuint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UpdateProcThreadAttribute(IntPtr attributes, uint flags, nuint attribute, IntPtr value, nuint size, IntPtr previous, IntPtr returnSize);
    [DllImport("kernel32.dll")]
    private static extern void DeleteProcThreadAttributeList(IntPtr attributes);
    [DllImport("kernel32.dll", EntryPoint = "CreateProcessW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateProcess(string application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint flags, string environment, string directory, ref StartupInfoEx startup, out ProcessInformation process);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CloseHandle(IntPtr handle);
}
