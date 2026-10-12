using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using PrimeSieve.App;
using PrimeSieve.Core;

internal static class Program
{
    private static int passed;
    private static readonly string Root = Path.Combine(Path.GetTempPath(), "PrimeSieve-ui-tests-" + Guid.NewGuid().ToString("N"));
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.FirstOrDefault() == "--slow-probe")
        {
            File.WriteAllText(args[1], Environment.ProcessId.ToString());
            Thread.Sleep(30000); return 0;
        }
        Directory.CreateDirectory(Root);
        // Supply the window's resources without App.xaml's automatic startup window.
        // Published-app smoke checks separately cover the full application styles.
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Resources["Accent"] = Brushes.OrangeRed;
        app.Resources["RelativeTime"] = new RelativeTimeConverter();
        app.Resources["ResultText"] = new Style(typeof(TextBlock));
        var exitCode = 1;
        app.Dispatcher.InvokeAsync(async () =>
        {
            try
            {
                await CloseDuringDiscovery(refresh: false);
                await CloseDuringDiscovery(refresh: true);
                await HistoryDetails();
                Console.WriteLine($"All {passed} WPF regression checks passed."); exitCode = 0;
            }
            catch (Exception error) { Console.Error.WriteLine(error); }
            finally
            {
                foreach (Window window in app.Windows.Cast<Window>().ToArray()) window.Close();
                app.Shutdown();
            }
        });
        app.Run();
        Directory.Delete(Root, true);
        return exitCode;
    }
    private static void Check(bool condition, string description)
    {
        if (!condition) throw new Exception("FAIL " + description);
        Console.WriteLine("PASS " + description); passed++;
    }
    private static async Task Until(Func<bool> condition, string description)
    {
        var watch = Stopwatch.StartNew();
        while (!condition())
        {
            if (watch.Elapsed > TimeSpan.FromSeconds(10)) throw new TimeoutException(description);
            await Task.Delay(25);
        }
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T item) yield return item;
            foreach (var descendant in Descendants<T>(child)) yield return descendant;
        }
    }
    private static Button Button(Window window, string content)
    {
        window.UpdateLayout();
        return Descendants<Button>(window).First(b => Equals(b.Content, content));
    }
    private static void Click(Button button) => button.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));

    private static async Task CloseDuringDiscovery(bool refresh)
    {
        var label = refresh ? "refresh" : "startup";
        var pidFile = Path.Combine(Root, label + ".pid");
        var calls = 0;
        var cancelled = false;
        async Task<RuntimeStatus[]> Discover(IReadOnlyDictionary<string, string> paths, CancellationToken token)
        {
            if (refresh && ++calls == 1) return [];
            try { await ProcessExecutor.RunAsync(Environment.ProcessPath!, ["--slow-probe", pidFile], timeoutSeconds: 30, cancellationToken: token); }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { cancelled = true; throw; }
            return [];
        }
        var window = new MainWindow(new SessionStore(Path.Combine(Root, label)), Discover);
        var closed = false;
        window.Closed += (_, _) => closed = true;
        window.Show();
        if (refresh)
        {
            await Until(() => window.IsIdle && calls == 1, "Initial discovery did not finish");
            Click(Button(window, "Refresh"));
        }
        await Until(() => File.Exists(pidFile), "Slow probe did not start");
        var pid = int.Parse(File.ReadAllText(pidFile));
        Check(!window.IsIdle, label + " discovery is in progress");
        var watch = Stopwatch.StartNew();
        window.Close(); // The same Closing event used by the window's close button.
        // Repeated close requests must not dispose/cancel the CTS twice or reopen the window.
        if (!closed) window.Close();
        await Until(() => closed, "Window did not close after cancelling discovery");
        Check(cancelled && watch.Elapsed.TotalSeconds < 5, label + " close cancels discovery and closes promptly");
        var exited = false;
        try { using var process = Process.GetProcessById(pid); exited = process.HasExited || process.WaitForExit(1000); }
        catch (ArgumentException) { exited = true; }
        Check(exited, label + " close terminates the active probe");
    }
    private static async Task HistoryDetails()
    {
        var store = new SessionStore(Path.Combine(Root, "history"));
        var future = new BenchmarkResult("future-language", "Future language", "saved runtime", "saved.exe", [11, 22, 33], 0,
            new(1, 2, 2), [], [], "saved-hash", [], []);
        var known = future with { Id = "csharp", Language = "C#" };
        var session = new BenchmarkSession { Configuration = new(1, 3), Completed = true, Results = [future, known] };
        store.Save(session);
        var window = new MainWindow(store, (_, _) => Task.FromResult(Array.Empty<RuntimeStatus>()));
        window.Show();
        await Until(() => window.IsIdle && window.History.Count == 1, "History did not load");
        Check(window.History.Single().Results[0].Id == future.Id, "unknown language history remains readable");
        ((TabControl)window.FindName("MainTabs")).SelectedIndex = 2;
        ((ListBox)window.FindName("HistoryList")).SelectedIndex = 0;
        Click(Button(window, "Open comparison"));
        var grid = (DataGrid)window.FindName("ResultsGrid");
        Check(window.Results.Count == 2, "history reopens unknown and known results");
        foreach (var result in window.Results.ToArray())
        {
            grid.SelectedItem = result;
            Exception? failure = null;
            var inspected = false;
            _ = window.Dispatcher.BeginInvoke(() =>
            {
                Window? details = null;
                try
                {
                    details = Application.Current.Windows.Cast<Window>().Single(w => w.Owner == window);
                    var code = Button(details, "Open calculation code");
                    var text = Descendants<TextBox>(details).Single().Text;
                    Check(text.Contains("saved runtime") && text.Contains("saved-hash") && text.Contains("11.0 ns"), result.Id + " details retain saved measurements");
                    Check(code.IsEnabled == (result.Id == "csharp"), result.Id + " code navigation availability");
                    if (result.Id == "csharp") Click(code);
                    else Check(text.Contains("not available in this version"), "unknown language details explain unavailable code");
                    inspected = true;
                }
                catch (Exception error) { failure = error; }
                finally { if (details?.IsVisible == true) details.Close(); }
            }, DispatcherPriority.Background);
            Click(Button(window, "Details")); // Enters the real modal details handler.
            if (failure != null) throw failure;
            Check(inspected, result.Id + " details dialog opens and closes without crashing");
            if (result.Id == "csharp")
                Check(((ComboBox)window.FindName("CodeLanguage")).SelectedItem is Language { Id: "csharp" }, "known language code navigation still works");
        }
        window.Close();
        Check(File.ReadAllText(Path.Combine(store.Root, "Sessions", session.Id + ".json")).Contains("future-language"), "viewing history preserves the original unknown-language record");
    }
}
