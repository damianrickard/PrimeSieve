using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using PrimeSieve.Core;

namespace PrimeSieve.App;

public sealed class LanguageChoice(RuntimeStatus status) : INotifyPropertyChanged
{
    public RuntimeStatus Status { get; } = status;
    public string Badge => Status.Available ? Status.Language.Runtime : "Not ready";
    private bool selected;
    public bool Selected { get => selected; set { selected = value; PropertyChanged?.Invoke(this, new(nameof(Selected))); } }
    public event PropertyChangedEventHandler? PropertyChanged;
}

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private readonly SessionStore store;
    private readonly Func<IReadOnlyDictionary<string, string>, CancellationToken, Task<RuntimeStatus[]>> discoverRuntimes;
    private Dictionary<string, string> overrides = [];
    private string preferencesWarning = "";
    public string PreferencesWarning => preferencesWarning;
    private BenchmarkSession? session;
    private CancellationTokenSource? cancellation;
    private CancellationTokenSource? discoveryCancellation;
    private bool closeAfterDiscovery;
    private bool busy;
    public bool IsIdle => !busy;
    public bool CanCancel => cancellation != null;
    public bool CanExport => IsIdle && session != null;
    public bool CanClearHistory => IsIdle && History.Count > 0;
    public ObservableCollection<LanguageChoice> Languages { get; } = [];
    public ObservableCollection<BenchmarkResult> Results { get; } = [];
    public ObservableCollection<BenchmarkSession> History { get; } = [];
    public string ReadySummary => $"{Languages.Count(l => l.Status.Available)} of {Languages.Count} detected";
    public string StatusText { get; private set; } = "Discovering installed languages…";
    public string ResultHeading { get; private set; } = "Ready to compare";
    public string ResultNotes { get; private set; } = "All processing and saved history stay on this computer.";
    public double ProgressValue { get; private set; }
    public event PropertyChangedEventHandler? PropertyChanged;
    public MainWindow() : this(DefaultStore(), (paths, token) => RuntimeDiscovery.DiscoverAsync(paths, token)) { }
    private static SessionStore DefaultStore()
    {
        var args = Environment.GetCommandLineArgs();
        return args.Length == 3 && args[1] == "--smoke-test" ? new(Path.Combine(Path.GetFullPath(args[2]), "state")) : new();
    }
    internal MainWindow(SessionStore store, Func<IReadOnlyDictionary<string, string>, CancellationToken, Task<RuntimeStatus[]>> discoverRuntimes)
    {
        this.store = store; this.discoverRuntimes = discoverRuntimes;
        InitializeComponent(); DataContext = this;
    }
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    private void RefreshState()
    {
        foreach (var name in new[] { nameof(IsIdle), nameof(CanCancel), nameof(CanExport), nameof(CanClearHistory), nameof(ReadySummary), nameof(StatusText), nameof(ResultHeading), nameof(ResultNotes), nameof(ProgressValue) }) Notify(name);
    }
    private void ShowError(Exception error) => MessageBox.Show(this, error.Message, "PrimeSieve", MessageBoxButton.OK, MessageBoxImage.Warning);
    private async void WindowLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            var preferences = store.LoadRuntimePreferences();
            overrides = preferences.Paths;
            preferencesWarning = string.Join("\n", preferences.Warnings); Notify(nameof(PreferencesWarning));
            LoadHistory();
            CodeLanguage.ItemsSource = PrimeSieve.Core.Language.All; SetupLanguage.ItemsSource = PrimeSieve.Core.Language.All;
            CodeLanguage.SelectedIndex = 0; SetupLanguage.SelectedIndex = 0;
            await DiscoverAsync();
            if (closeAfterDiscovery) return;
            var args = Environment.GetCommandLineArgs();
            if (args.Length == 3 && args[1] == "--smoke-test") await SmokeTestAsync(args[2]);
        }
        catch (Exception error) { ShowError(error); }
    }
    private async Task DiscoverAsync()
    {
        if (busy || closeAfterDiscovery) return;
        using var discovery = new CancellationTokenSource();
        discoveryCancellation = discovery;
        busy = true; StatusText = "Checking installed runtimes…"; RefreshState();
        var selected = Languages.Where(l => l.Selected).Select(l => l.Status.Language.Id).ToHashSet();
        var first = Languages.Count == 0;
        try
        {
            var statuses = await discoverRuntimes(new Dictionary<string, string>(overrides), discovery.Token);
            discovery.Token.ThrowIfCancellationRequested();
            Languages.Clear();
            foreach (var status in statuses) Languages.Add(new(status) { Selected = status.Available && (first || selected.Contains(status.Language.Id)) });
            StatusText = ReadySummary + ". Choose a workload and start a comparison.";
            UpdateSetup();
        }
        catch (OperationCanceledException) when (discovery.IsCancellationRequested) { }
        finally
        {
            discoveryCancellation = null; busy = false; RefreshState();
            if (closeAfterDiscovery) Close();
        }
    }
    private async void RefreshClicked(object sender, RoutedEventArgs e) { try { await DiscoverAsync(); } catch (Exception error) { ShowError(error); } }
    private void SelectAll(object sender, RoutedEventArgs e) { foreach (var language in Languages) language.Selected = language.Status.Available; }
    private void SelectNone(object sender, RoutedEventArgs e) { foreach (var language in Languages) language.Selected = false; }
    private void PresetClicked(object sender, RoutedEventArgs e) => PrimeCountBox.Text = ((Button)sender).Tag.ToString();
    private void ModeChanged(object sender, SelectionChangedEventArgs e) { if (WarmupsBox != null) WarmupsBox.IsEnabled = ModeBox.SelectedIndex == 0; }
    private BenchmarkConfiguration ReadConfiguration()
    {
        if (!int.TryParse(PrimeCountBox.Text, NumberStyles.AllowThousands, CultureInfo.CurrentCulture, out var count) ||
            !int.TryParse(IterationsBox.Text, out var runs) || !int.TryParse(WarmupsBox.Text, out var warm) ||
            !double.TryParse(TimeoutBox.Text, out var timeout)) throw new ArgumentException("Enter valid numbers for the workload and timing settings.");
        var config = new BenchmarkConfiguration(count, runs, ModeBox.SelectedIndex == 1 ? 0 : warm, timeout, ModeBox.SelectedIndex == 0 ? TimingMode.Calculation : TimingMode.Startup);
        config.Validate(); return config;
    }
    private async void StartClicked(object sender, RoutedEventArgs e) { try { await RunComparisonAsync(); } catch (Exception error) { ShowError(error); } }
    private async Task RunComparisonAsync()
    {
        if (busy) return;
        var config = ReadConfiguration();
        var selected = Languages.Where(l => l.Selected && l.Status.Available).Select(l => l.Status).ToArray();
        if (selected.Length == 0) throw new ArgumentException("Select at least one detected language.");
        busy = true; cancellation = new(); session = null; Results.Clear(); ProgressValue = 0;
        ResultHeading = $"{config.PrimeCount:N0} primes • {config.Repetitions} iterations";
        ResultNotes = config.Mode == TimingMode.Calculation ? "Calculation only. Warm-ups excluded; each completed result is independently verified." : "Startup + calculation. Fresh processes; no warm-ups. Compilation excluded.";
        MainTabs.SelectedIndex = 0; RefreshState();
        var receivingProgress = true;
        var progress = new Progress<BenchmarkEvent>(update =>
        {
            if (!receivingProgress) return;
            StatusText = update.Message; ProgressValue = 100.0 * update.Finished / Math.Max(1, update.Total);
            if (update.Result != null) AddResult(update.Result);
            RefreshState();
        });
        try
        {
            session = await BenchmarkRunner.RunAsync(selected, config, new Dictionary<string, string>(overrides), progress, cancellation.Token);
            receivingProgress = false;
            Results.Clear(); foreach (var result in session.Results) Results.Add(result);
            StatusText = session.Cancelled ? "Cancelled. Completed results were kept." : $"Comparison complete • {session.Results.Count} verified • {session.Failures.Count} failed";
            ResultNotes += session.Failures.Count == 0 ? "" : "\n" + string.Join("\n", session.Failures.Select(f => f.Key + ": " + f.Value));
            try { store.Save(session); LoadHistory(); }
            catch (Exception error) { StatusText += " • History could not be saved: " + error.Message; }
        }
        finally { receivingProgress = false; cancellation.Dispose(); cancellation = null; busy = false; RefreshState(); }
    }
    private void AddResult(BenchmarkResult result)
    {
        var index = 0; while (index < Results.Count && Results[index].MedianNS <= result.MedianNS) index++;
        Results.Insert(index, result);
    }
    private void CancelClicked(object sender, RoutedEventArgs e) { cancellation?.Cancel(); StatusText = "Cancelling worker…"; RefreshState(); }
    private void WindowClosing(object? sender, CancelEventArgs e)
    {
        if (!busy) return;
        e.Cancel = true;
        if (discoveryCancellation != null)
        {
            closeAfterDiscovery = true;
            StatusText = "Stopping runtime checks and closing…"; RefreshState();
            discoveryCancellation.Cancel();
            return;
        }
        if (cancellation != null) { cancellation.Cancel(); StatusText = "Cancelling. Close the window after the worker stops."; RefreshState(); }
    }
    private void LoadHistory()
    {
        var loaded = store.Load(); History.Clear(); foreach (var item in loaded.Sessions) History.Add(item);
        if (loaded.Errors.Count > 0) ResultNotes = $"{loaded.Errors.Count} unreadable history files were skipped. " + string.Join("\n", loaded.Errors);
        RefreshState();
    }
    private void OpenHistory(object sender, RoutedEventArgs e)
    {
        if (busy || HistoryList.SelectedItem is not BenchmarkSession saved) return;
        PrimeCountBox.Text = saved.Configuration.PrimeCount.ToString(); IterationsBox.Text = saved.Configuration.Repetitions.ToString();
        WarmupsBox.Text = saved.Configuration.Warmups.ToString(); TimeoutBox.Text = saved.Configuration.TimeoutSeconds.ToString(CultureInfo.CurrentCulture);
        ModeBox.SelectedIndex = saved.Configuration.Mode == TimingMode.Calculation ? 0 : 1;
        session = saved; Results.Clear(); foreach (var result in saved.Results.OrderBy(r => r.MedianNS)) Results.Add(result);
        ResultHeading = $"{saved.Configuration.PrimeCount:N0} primes • {saved.Configuration.Repetitions} iterations";
        ResultNotes = $"{saved.Date:g} • {saved.Configuration.Mode} • {saved.Machine}" + (saved.Cancelled ? " • Cancelled" : "") + "\n" + string.Join("\n", saved.Failures.Select(f => f.Key + ": " + f.Value));
        MainTabs.SelectedIndex = 0; StatusText = "Opened saved comparison."; RefreshState();
    }
    private void HistoryDoubleClicked(object sender, MouseButtonEventArgs e) => OpenHistory(sender, e);
    private void ClearHistory(object sender, RoutedEventArgs e)
    {
        if (!CanClearHistory || MessageBox.Show(this, "Delete all saved comparisons? Current results and exported files will be kept.", "Clear history", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        try { store.Clear(); LoadHistory(); StatusText = "Saved history cleared."; RefreshState(); } catch (Exception error) { ShowError(error); }
    }
    private void Export(bool csv)
    {
        if (session == null || busy) return;
        var dialog = new SaveFileDialog { Filter = csv ? "CSV files|*.csv" : "JSON files|*.json", FileName = $"PrimeSieve-{session.Date:yyyyMMdd-HHmmss}", AddExtension = true };
        if (dialog.ShowDialog(this) != true) return;
        try { if (csv) SessionStore.ExportCsv(session, dialog.FileName); else SessionStore.ExportJson(session, dialog.FileName); StatusText = "Exported " + dialog.FileName; RefreshState(); }
        catch (Exception error) { ShowError(error); }
    }
    private void ExportJsonClicked(object sender, RoutedEventArgs e) => Export(false);
    private void ExportCsvClicked(object sender, RoutedEventArgs e) => Export(true);
    private void ResultDetailsClicked(object sender, RoutedEventArgs e) => ShowResultDetails();
    private void ResultDoubleClicked(object sender, MouseButtonEventArgs e) => ShowResultDetails();
    private void ResultKeyDown(object sender, KeyEventArgs e) { if (e.Key == Key.Enter) { e.Handled = true; ShowResultDetails(); } }
    private void ShowResultDetails()
    {
        if (ResultsGrid.SelectedItem is not BenchmarkResult result) return;
        var language = PrimeSieve.Core.Language.All.FirstOrDefault(l => l.Id == result.Id);
        var note = language?.Note ?? "Calculation code for this language is not available in this version. Saved measurements are shown above.";
        var details = $"{result.Language}\n{result.RuntimeVersion}\n{result.ExecutablePath}\n\nMedian: {result.MedianDisplay}    Mean: {result.MeanDisplay}\n{result.Iterations} iterations • {result.RangeDisplay}\nSamples: {string.Join(", ", result.SamplesNS.Select(TimeDisplay.Format))}\nPreparation: {result.CompilationSeconds:F3} s\nLast prime: {result.Signature.LastPrime:N0}    Checksum: {result.Signature.Checksum}\n\nSource SHA-256 (manifest v{result.SourceHashFormat}):\n{result.SourceHash}\n\nBuild:\n{JsonSerializer.Serialize(result.Command)}\n\nLaunch:\n{JsonSerializer.Serialize(result.LaunchCommand)}\n\nHelpers:\n{JsonSerializer.Serialize(result.HelperTools, JsonDefaults.Options)}\n\n{note}";
        var panel = new DockPanel { Margin = new Thickness(20) };
        var code = new Button { Content = "Open calculation code", IsEnabled = language != null, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 14, 0, 0) };
        DockPanel.SetDock(code, Dock.Bottom); panel.Children.Add(code);
        panel.Children.Add(new TextBox { Text = details, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        var window = new Window { Owner = this, Title = result.Language + " — result details", Width = 760, Height = 620, Content = panel, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        code.Click += (_, _) => { if (language == null) return; CodeLanguage.SelectedItem = language; MainTabs.SelectedIndex = 1; window.Close(); };
        window.ShowDialog();
    }
    private void CodeSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (CodeLanguage.SelectedItem is not Language language || CodeText == null) return;
        try { CodeText.Text = string.Join("\n\n", WorkerSources.Sections(language).Select(s => $"── {s.Title} · line {s.SourceLine} ──\n{s.Code}")); }
        catch (Exception error) { CodeText.Text = error.Message; }
    }
    private void SmallerCode(object sender, RoutedEventArgs e) => CodeText.FontSize = Math.Max(10, CodeText.FontSize - 1);
    private void LargerCode(object sender, RoutedEventArgs e) => CodeText.FontSize = Math.Min(24, CodeText.FontSize + 1);
    private void CopyCode(object sender, RoutedEventArgs e) { try { Clipboard.SetText(CodeText.Text); } catch (Exception error) { ShowError(error); } }
    private void SetupSelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateSetup();
    private void UpdateSetup()
    {
        if (SetupLanguage.SelectedItem is not Language language || RuntimePath == null) return;
        SetupAdvice.Text = language.SetupAdvice + (string.IsNullOrEmpty(language.Note) ? "" : "\n\n" + language.Note);
        var status = Languages.FirstOrDefault(l => l.Status.Language.Id == language.Id)?.Status;
        RuntimePath.Text = overrides.GetValueOrDefault(language.Id) ?? status?.Executable ?? "";
        SetupStatus.Text = (status?.Version ?? "Not checked") + "\n" + (status?.Executable ?? "");
    }
    private void BrowseRuntime(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Filter = "Executables|*.exe;*.cmd;*.bat|All files|*.*" };
        if (dialog.ShowDialog(this) == true) RuntimePath.Text = dialog.FileName;
    }
    private async void SaveRuntime(object sender, RoutedEventArgs e)
    {
        if (SetupLanguage.SelectedItem is not Language language) return;
        try
        {
            var path = RuntimePath.Text.Trim().Trim('"');
            if (!Path.IsPathFullyQualified(path) || !File.Exists(path)) throw new ArgumentException("Choose an existing executable using its full path.");
            var updated = new Dictionary<string, string>(overrides) { [language.Id] = path };
            store.SaveOverrides(updated); overrides = updated; preferencesWarning = ""; Notify(nameof(PreferencesWarning)); await DiscoverAsync();
        }
        catch (Exception error) { ShowError(error); }
    }
    private async void ResetRuntime(object sender, RoutedEventArgs e)
    {
        if (SetupLanguage.SelectedItem is not Language language) return;
        try { var updated = new Dictionary<string, string>(overrides); updated.Remove(language.Id); store.SaveOverrides(updated); overrides = updated; preferencesWarning = ""; Notify(nameof(PreferencesWarning)); await DiscoverAsync(); } catch (Exception error) { ShowError(error); }
    }
    private async Task SmokeTestAsync(string outputDirectory)
    {
        // Opt-in, unattended Windows UI check. Normal launches never run benchmarks automatically.
        Directory.CreateDirectory(outputDirectory);
        try
        {
            PrimeCountBox.Text = "10000"; IterationsBox.Text = "3"; WarmupsBox.Text = "1";
            SelectAll(this, new RoutedEventArgs());
            await RunComparisonAsync();
            if (session == null || session.Results.Count == 0 || session.Failures.Count != 0) throw new InvalidOperationException("UI benchmark failed: " + ResultNotes);
            SessionStore.ExportJson(session, Path.Combine(outputDirectory, "ui-results.json"));
            SessionStore.ExportCsv(session, Path.Combine(outputDirectory, "ui-results.csv"));
            ModeBox.SelectedIndex = 1;
            await RunComparisonAsync();
            if (session == null || session.Configuration.Mode != TimingMode.Startup || session.Results.Count == 0 || session.Failures.Count != 0)
                throw new InvalidOperationException("UI startup benchmark failed: " + ResultNotes);
            SessionStore.ExportJson(session, Path.Combine(outputDirectory, "ui-startup-results.json"));
            await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            Capture(Path.Combine(outputDirectory, "results.png"));
            HistoryList.SelectedItem = History.First(s => s.Id == session.Id);
            OpenHistory(this, new RoutedEventArgs());
            if (Results.Count != session.Results.Count) throw new InvalidOperationException("History reopen failed.");
            PrimeCountBox.Text = "0";
            var invalidRejected = false;
            try { _ = ReadConfiguration(); } catch (ArgumentException) { invalidRejected = true; }
            if (!invalidRejected) throw new InvalidOperationException("UI accepted an invalid workload.");
            PrimeCountBox.Text = "10000";
            CodeLanguage.SelectedItem = PrimeSieve.Core.Language.All.First(l => l.Id == "csharp"); MainTabs.SelectedIndex = 1;
            await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (!CodeText.Text.Contains("new byte")) throw new InvalidOperationException("Code explorer failed.");
            Capture(Path.Combine(outputDirectory, "code.png"));
            SetupLanguage.SelectedItem = PrimeSieve.Core.Language.All.First(l => l.Id == "csharp"); MainTabs.SelectedIndex = 3;
            await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            if (!SetupStatus.Text.Contains("dotnet")) throw new InvalidOperationException("Runtime setup did not show the detected path.");
            Capture(Path.Combine(outputDirectory, "setup.png"));
            MainTabs.SelectedIndex = 0; Width = MinWidth; Height = MinHeight;
            await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);
            await Task.Delay(300);
            if (ResultsGrid.ActualHeight < 120) throw new InvalidOperationException("Results are too short at minimum window size.");
            Capture(Path.Combine(outputDirectory, "minimum-size.png"));
            File.WriteAllText(Path.Combine(outputDirectory, "ui-smoke.json"), JsonSerializer.Serialize(new { passed = true, session.Results.Count, history = History.Count, startup = true, preferencesWarning, codeExplorer = true, historyReopened = true, invalidInputRejected = true, runtimeSetup = true, width = ActualWidth, height = ActualHeight }));
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(outputDirectory, "ui-smoke.json"), JsonSerializer.Serialize(new { passed = false, error = error.ToString() })); }
        finally { Close(); }
    }
    private void Capture(string path)
    {
        UpdateLayout();
        var content = (FrameworkElement)Content;
        var image = new RenderTargetBitmap((int)content.ActualWidth, (int)content.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        image.Render(content); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = File.Create(path); encoder.Save(stream);
    }
}
