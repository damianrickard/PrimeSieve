import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PrimeSieveCore

@MainActor
final class AppModel: ObservableObject {
    @Published var runtimes: [RuntimeStatus] = []
    @Published var selected = Set(["assembly", "c", "cpp", "swift", "python", "javascript", "ruby", "perl", "lua", "pascal"])
    @Published var primeCount = "100000"
    @Published var repetitions = 7
    @Published var warmups = 3
    @Published var timeout = 120.0
    @Published var mode: TimingMode = .calculation
    @Published var workload: Workload = .firstN
    @Published var upperLimit = "1000000"
    @Published var variants: ImplementationSelection = .baseline
    @Published var rounds = 1
    @Published var seconds = 5.0
    @Published var storageFilter = "All storage"

    @Published var isRunning = false
    @Published var isDiscovering = false
    @Published var progress = 0.0
    @Published var status = "Checking installed languages…"
    @Published var session: BenchmarkSession?
    @Published var history: [BenchmarkSession] = []
    @Published var errorMessage: String?
    @Published var overrides = UserDefaults.standard.dictionary(forKey: "runtimePaths") as? [String: String] ?? [:]

    private let discover: @Sendable ([String: String]) async -> [RuntimeStatus]
    private var needsRefresh = false
    private let historyDirectory: URL

    init(discover: @escaping @Sendable ([String: String]) async -> [RuntimeStatus] = { await RuntimeDiscovery.discover(overrides: $0) },
         historyDirectory: URL = SessionStore.directory) {
        self.discover = discover
        self.historyDirectory = historyDirectory
        history = SessionStore.load(directory: historyDirectory)
        let defaults = UserDefaults.standard
        if let ids = defaults.stringArray(forKey: "selectedLanguages") { selected = Set(ids) }
        if let data = defaults.data(forKey: "configuration"),
           let config = try? JSONDecoder().decode(BenchmarkConfiguration.self, from: data),
           (try? config.validate()) != nil {
            primeCount = String(config.primeCount); repetitions = config.repetitions
            warmups = config.warmups; timeout = config.timeoutSeconds; mode = config.mode
            workload = config.workload; upperLimit = String(config.upperLimit); variants = config.implementations; rounds = config.rounds; seconds = config.durationSeconds
        }
    }

    var preferenceSignature: String {
        [primeCount, upperLimit, workload.rawValue, variants.rawValue, String(rounds), String(seconds), String(repetitions), String(warmups), String(timeout), mode.rawValue, selected.sorted().joined(separator: ",")].joined(separator: "|")
    }
    func savePreferences() {
        UserDefaults.standard.set(selected.sorted(), forKey: "selectedLanguages")
        if let config = configuration, (try? config.validate()) != nil,
           let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "configuration")
        }
    }

    var results: [BenchmarkResult] {
        (session?.results ?? []).filter { storageFilter == "All storage" || (storageFilter == "Packed bits" ? $0.implementation?.bits == 1 : $0.implementation?.bits == 8) }.sorted(by: BenchmarkResult.faster)
    }
    var selectedImplementationCount: Int {
        guard let configuration else { return 0 }
        return selectedReady.flatMap { SieveImplementation.selected(for: $0.id, configuration: configuration) }.count
    }
    func dragRacePreset() {
        workload = .upperLimit; upperLimit = "1000000"; mode = .throughput
        variants = .candidates; seconds = 5; repetitions = 1; rounds = 3
        selected = Set(runtimes.filter { $0.available && ["python", "swift", "fortran", "assembly", "r"].contains($0.id) }.map(\.id))
    }
    var readyCount: Int { runtimes.filter(\.available).count }
    var selectedReady: [RuntimeStatus] { runtimes.filter { $0.available && selected.contains($0.id) } }
    var configuration: BenchmarkConfiguration? {
        let parsedCount = Int(primeCount.replacingOccurrences(of: ",", with: ""))
        let parsedLimit = Int(upperLimit.replacingOccurrences(of: ",", with: ""))
        guard workload == .firstN ? parsedCount != nil : parsedLimit != nil else { return nil }
        // Preserve valid inactive values for switching back, but never let hidden input block a run.
        let count = workload == .firstN ? parsedCount! : parsedCount.flatMap { (1...10_000_000).contains($0) ? $0 : nil } ?? 100_000
        let limit = workload == .upperLimit ? parsedLimit! : parsedLimit.flatMap { (2...200_000_000).contains($0) ? $0 : nil } ?? 1_000_000
        return .init(primeCount: count, repetitions: repetitions, warmups: warmups, timeoutSeconds: timeout, mode: mode, workload: workload, upperLimit: limit, durationSeconds: seconds, rounds: rounds, implementations: variants)
    }

    func refresh() async {
        guard !isRunning else { return }
        if isDiscovering { needsRefresh = true; return }
        isDiscovering = true
        repeat {
            needsRefresh = false
            let paths = overrides
            let discover = self.discover
            let discovered = await Task.detached { await discover(paths) }.value
            // Discard a stale snapshot and keep Run disabled until the latest selection is ready.
            if !needsRefresh { runtimes = discovered }
        } while needsRefresh
        isDiscovering = false
        status = "\(readyCount) of 35 languages ready"
    }

    func run() {
        guard !isRunning, !isDiscovering else { return }
        guard let config = configuration else {
            errorMessage = workload == .firstN ? "Enter a whole number for the prime count." : "Enter a whole number for the inclusive upper limit."
            return
        }
        do { try config.validate() } catch { errorMessage = error.localizedDescription; return }
        let languages = selectedReady
        guard !languages.isEmpty else { errorMessage = "Select at least one installed language."; return }
        isRunning = true; progress = 0; session = BenchmarkSession(configuration: config)
        let owner = self
        let paths = overrides
        let worker = Task.detached { [owner] in
            do {
                let result = try await BenchmarkRunner.run(statuses: languages, configuration: config, overrides: paths) { event in
                    await owner.receive(event)
                }
                await owner.finish(result)
            } catch is CancellationError { await owner.cancelled() }
            catch { await owner.failed(error.localizedDescription) }
        }
        // Retain the actual detached task so cancellation reaches its process supervisor.
        detachedTask = worker
    }
    private var detachedTask: Task<Void, Never>?
    func cancel() { status = "Stopping the current worker…"; detachedTask?.cancel() }

    private func receive(_ event: BenchmarkEvent) {
        switch event {
        case .preparingReference: status = "Calculating the independent correctness reference…"
        case .preparing(let language, let index, let total):
            status = "Preparing \(language) • \(index + 1) of \(total)"; progress = 0
        case .measuring(let language, let index, let total):
            status = "Measuring \(language) • \(index + 1) of \(total)"
            progress = Double(index) / Double(max(1, total))
        case .roundOrder(let order): session?.executionOrder?.append(order)
        case .result: break // A partial round is progress, not a comparable set of scores.
        case .roundCompleted(let results): session?.results = results
        case .failure(let language, let error):
            session?.results.removeAll { $0.id == language }; session?.failures[language] = error
        }
    }
    private func finish(_ result: BenchmarkSession) {
        session = result; isRunning = false; progress = 1
        status = "Finished • \(result.results.count) verified • \(result.failures.count) failed"
        save(); detachedTask = nil
    }
    private func cancelled() {
        isRunning = false; status = "Cancelled • only completed rounds retained"
        save(); detachedTask = nil
    }
    private func failed(_ error: String) {
        isRunning = false; status = "Comparison stopped"; errorMessage = error
        save(); detachedTask = nil
    }
    private func save() {
        guard let session, !session.results.isEmpty || !session.failures.isEmpty else { return }
        do { try SessionStore.save(session, directory: historyDirectory); history = SessionStore.load(directory: historyDirectory) }
        catch { errorMessage = "The results are available, but history could not be saved: \(error.localizedDescription)" }
    }
    /// Keep the visible result available for export, and refresh the list even after partial failure.
    func clearHistory() -> String? {
        guard !isRunning else { return "Stop the current comparison before clearing history." }
        defer { history = SessionStore.load(directory: historyDirectory) }
        do { try SessionStore.clear(directory: historyDirectory); return nil }
        catch { return "History could not be fully cleared: \(error.localizedDescription)" }
    }
    func selectHistory(_ value: BenchmarkSession) {
        guard !isRunning else { return }
        session = value
        primeCount = String(value.configuration.primeCount)
        repetitions = value.configuration.repetitions; warmups = value.configuration.warmups
        mode = value.configuration.mode; timeout = value.configuration.timeoutSeconds
        workload = value.configuration.workload; upperLimit = String(value.configuration.upperLimit)
        variants = value.configuration.implementations; rounds = value.configuration.rounds; seconds = value.configuration.durationSeconds
        progress = value.completed ? 1 : 0
        status = "Saved comparison • \(value.date.formatted(date: .abbreviated, time: .shortened))"
    }
    func export(json: Bool) {
        guard let session else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [json ? .json : .commaSeparatedText]
        panel.nameFieldStringValue = "PrimeSieve-\(session.configuration.primeCount).\(json ? "json" : "csv")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = json ? try SessionStore.json(session) : Data(SessionStore.csv(session).utf8)
            try data.write(to: url, options: .atomic)
        } catch { errorMessage = "Export failed: \(error.localizedDescription)" }
    }
    func chooseRuntime(_ language: Language) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Choose the \(language.executables.first ?? language.runtime) executable for \(language.name)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        overrides[language.id] = url.path
        UserDefaults.standard.set(overrides, forKey: "runtimePaths")
        Task { await refresh() }
    }
    func clearRuntime(_ language: Language) {
        overrides.removeValue(forKey: language.id)
        UserDefaults.standard.set(overrides, forKey: "runtimePaths")
        Task { await refresh() }
    }
}
