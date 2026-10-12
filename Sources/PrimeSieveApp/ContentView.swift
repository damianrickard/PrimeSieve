import SwiftUI
import PrimeSieveCore

@MainActor
private final class ContentState: ObservableObject {
    @Published var search = ""
    @Published var showSetup = false
    @Published var showHistory = false
    @Published var confirmClearHistory = false
    @Published var historyError: String?
    @Published var detail: BenchmarkResult?
    @Published var selectedResult: String?
    @Published var showCode = false
}

/// International orange (aerospace): #FF4F00 in the sRGB color space.
let accent = Color(.sRGB, red: 1, green: 79.0 / 255.0, blue: 0, opacity: 1)

struct ContentView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = ContentState()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 245)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                header
                configuration
                if model.isRunning {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.status).font(.callout)
                            Spacer()
                            Text("Provisional rankings").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: model.progress).tint(accent)
                    }
                } else { Text(model.status).font(.callout).foregroundStyle(.secondary) }
                if model.results.isEmpty { emptyState }
                else { chart; leaderboard }
                if let failures = model.session?.failures, !failures.isEmpty {
                    DisclosureGroup("\(failures.count) language\(failures.count == 1 ? "" : "s") could not complete") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(failures.keys.sorted(), id: \.self) { language in
                                    Text("\(language): \(failures[language] ?? "")").font(.caption).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 100)
                    }.foregroundStyle(.orange)
                }
                footer
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .tint(accent)
        .onChange(of: model.preferenceSignature) { _, _ in model.savePreferences() }
        .sheet(isPresented: $ui.showSetup) { SetupView(model: model) }
        .sheet(isPresented: $ui.showHistory) { history }
        .sheet(isPresented: $ui.showCode) { CodeExplorerView() }
        .sheet(item: $ui.detail, onDismiss: { ui.selectedResult = nil }) { ResultDetail(result: $0) }
        .alert("PrimeSieve", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("LANGUAGES", systemImage: "checklist").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(model.selectedReady.count) selected · \(model.readyCount) ready").font(.caption)
            TextField("Find a language", text: $ui.search).textFieldStyle(.roundedBorder)
            HStack {
                Button("All ready") { model.selected = Set(model.runtimes.filter(\.available).map(\.id)) }
                Button("Clear") { model.selected.removeAll() }
            }.font(.caption).disabled(model.isRunning || model.isDiscovering)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Language.all.filter { ui.search.isEmpty || $0.name.localizedCaseInsensitiveContains(ui.search) }) { language in
                        let runtime = model.runtimes.first { $0.id == language.id }
                        let available = runtime?.available == true
                        Button {
                            if model.selected.contains(language.id) { model.selected.remove(language.id) }
                            else { model.selected.insert(language.id) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: model.selected.contains(language.id) && available ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(available ? accent : Color.secondary.opacity(0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(language.name).font(.system(size: 13, weight: .medium)).foregroundStyle(available ? .primary : .secondary)
                                    Text(available ? language.runtime : "Needs setup").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Circle().fill(available ? accent : Color.secondary.opacity(0.3)).frame(width: 5, height: 5)
                            }.padding(.vertical, 7).padding(.horizontal, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!available || model.isRunning || model.isDiscovering)
                        .help(runtime?.version ?? "Checking runtime")
                    }
                }
            }
            Divider()
            Button { ui.showSetup = true } label: { Label("Language setup", systemImage: "wrench.and.screwdriver") }
                .buttonStyle(.plain).disabled(model.isRunning || model.isDiscovering)
            Button { Task { await model.refresh() } } label: { Label("Refresh availability", systemImage: "arrow.clockwise") }
                .buttonStyle(.plain).disabled(model.isRunning || model.isDiscovering)
        }.padding(.horizontal, 18).padding(.top, 40).padding(.bottom, 20)
        .background(.quaternary.opacity(0.35))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Image(systemName: "number.square.fill").font(.system(size: 30)).foregroundStyle(accent)
                    Text("PrimeSieve").font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Text("35 languages. One workload.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { ui.showCode = true } label: { Label("Code explorer", systemImage: "chevron.left.forwardslash.chevron.right") }
            Button { ui.showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }.disabled(model.isRunning)
            Menu {
                Button("Export CSV…") { model.export(json: false) }
                Button("Export JSON…") { model.export(json: true) }
            } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .disabled(model.session == nil || model.isRunning)
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRIMES TO FIND").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("100000", text: $model.primeCount).font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .textFieldStyle(.roundedBorder).frame(width: 195).disabled(model.isRunning)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("MEASURE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Timing mode", selection: $model.mode) {
                        ForEach(TimingMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 185).disabled(model.isRunning)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("ITERATIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("Measured iterations per language", selection: $model.repetitions) {
                        ForEach(1...30, id: \.self) { Text("\($0)×").tag($0) }
                    }.labelsHidden().frame(width: 80).disabled(model.isRunning)
                    .help("Run each language this many times. Warm-ups are excluded from mean and median.")
                }
                Spacer()
                if model.isRunning {
                    Button { model.cancel() } label: { Label("Cancel", systemImage: "stop.fill").frame(width: 135, height: 30) }
                } else {
                    Button { model.run() } label: { Label("Run comparison", systemImage: "play.fill").frame(width: 135, height: 30) }
                        .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(accent, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.black)
                        .disabled(model.selectedReady.isEmpty || model.isDiscovering)
                }
            }
            HStack(spacing: 8) {
                Text("Presets").font(.caption).foregroundStyle(.secondary)
                ForEach([10_000, 100_000, 1_000_000], id: \.self) { count in
                    Button(count.formatted()) { model.primeCount = String(count) }.font(.caption)
                }
            }.disabled(model.isRunning)
            DisclosureGroup("Advanced settings") {
                HStack(spacing: 24) {
                    Stepper("\(model.warmups) warm-up runs", value: $model.warmups, in: 0...20).disabled(model.mode == .startup)
                    Picker("Timeout", selection: $model.timeout) {
                        Text("30 s").tag(30.0); Text("2 min").tag(120.0); Text("10 min").tag(600.0)
                    }.frame(width: 155)
                }.padding(.top, 8)
            }.font(.callout).disabled(model.isRunning)
            Text(model.mode == .calculation
                 ? "Each language runs \(model.repetitions) measured iterations after warm-up. Mean and median exclude compilation, validation and output."
                 : "Each language launches \(model.repetitions) fresh processes. Mean and median include startup and calculation; compilation is excluded.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 54, weight: .light)).foregroundStyle(accent)
            Text(model.isRunning ? "The first result is on its way" : "Put your languages to the test")
                .font(.title2.weight(.semibold))
            Text(model.isRunning ? "Each result is verified before joining the leaderboard." : "Choose languages, set a prime count, and start a comparison.\nVerified results will cascade from fastest to slowest.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
            if !model.isRunning { Text("Single-threaded · Local execution · No account required").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FASTEST LANGUAGES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Median · lower is faster").font(.caption).foregroundStyle(.secondary)
            }
            let leaders = Array(model.results.prefix(8))
            let maximum = leaders.map(\.medianNS).max() ?? 1
            VStack(spacing: 7) {
                ForEach(leaders) { result in
                    HStack(spacing: 12) {
                        Text(result.language).font(.caption).frame(width: 100, alignment: .leading)
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent.gradient)
                                .frame(width: maximum > 0 ? max(2, geometry.size.width * CGFloat(result.medianNS / maximum)) : 2, height: 10)
                        }.frame(height: 10)
                        Text(TimeDisplay.format(result.medianNS)).font(.caption.monospacedDigit())
                            .frame(width: 85, alignment: .trailing).foregroundStyle(.secondary)
                    }.frame(height: 15)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEADERBOARD").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("Click a row for details").font(.caption).foregroundStyle(.secondary)
            }
            Table(model.results, selection: $ui.selectedResult) {
                TableColumn("#") { result in Text(String((model.results.firstIndex { $0.id == result.id } ?? 0)+1)).foregroundStyle(.secondary) }.width(26)
                TableColumn("Language") { result in
                    Text(result.language).fontWeight(.medium)
                }.width(min: 95, ideal: 110)
                TableColumn("Mean") { Text(TimeDisplay.format($0.meanNS)).monospacedDigit() }.width(min: 75, ideal: 85)
                TableColumn("Median") { Text(TimeDisplay.format($0.medianNS)).monospacedDigit().foregroundStyle(accent) }.width(min: 75, ideal: 85)
                TableColumn("Fastest") { Text(TimeDisplay.format($0.minimumNS)).monospacedDigit() }.width(min: 75, ideal: 85)
                TableColumn("Slowest") { Text(TimeDisplay.format($0.maximumNS)).monospacedDigit() }.width(min: 75, ideal: 85)
                TableColumn("Relative") { result in
                    if let first = model.results.first, first.medianNS > 0 {
                        Text(String(format: "%.2f×", result.medianNS/first.medianNS)).monospacedDigit()
                    } else { Text("—") }
                }.width(70)
                TableColumn("Final prime") { Text($0.signature.lastPrime.formatted()).monospacedDigit() }.width(min: 90, ideal: 110)
                TableColumn("Verified") { _ in Image(systemName: "checkmark.seal.fill").foregroundStyle(accent) }.width(65)
            }.frame(minHeight: 125)
                .onChange(of: ui.selectedResult) { _, id in
                    if let id { ui.detail = model.results.first { $0.id == id } }
                }
        }
    }

    private var footer: some View {
        HStack(alignment: .top) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text("Compares these implementations on this Mac. Runtimes and storage differ; small timing gaps may be noise. Language order is randomized per comparison.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(BenchmarkSession.architecture).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Saved comparisons").font(.title2.weight(.semibold))
                Spacer()
                Button("Clear History…", role: .destructive) { ui.confirmClearHistory = true }
                    .disabled(model.history.isEmpty || model.isRunning)
                Button("Done") { ui.showHistory = false }
            }
            if model.history.isEmpty { Text("Completed comparisons will appear here.").foregroundStyle(.secondary).padding(.vertical, 50) }
            else {
                List(model.history) { session in
                    Button {
                        model.selectHistory(session); ui.showHistory = false
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(session.configuration.primeCount.formatted()) primes · \(session.results.count) languages")
                            Text("\(session.date.formatted()) · \(session.configuration.mode.rawValue)\(session.completed ? "" : " · Partial")").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(24).frame(width: 620, height: 420)
        .alert("Clear all saved comparisons?", isPresented: $ui.confirmClearHistory) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) { ui.historyError = model.clearHistory() }
        } message: {
            Text("This permanently deletes your saved comparison history. Results currently on screen and exported files are kept.")
        }
        .alert("Couldn’t clear history", isPresented: Binding(get: { ui.historyError != nil }, set: { if !$0 { ui.historyError = nil } })) {
            Button("OK") { ui.historyError = nil }
        } message: { Text(ui.historyError ?? "") }
    }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Language setup").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("PrimeSieve uses compilers and runtimes installed on your Mac. Install the languages you want, then refresh. Apple’s Command Line Tools provide C, C++, assembly and Swift.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Language.all) { language in
                        let runtime = model.runtimes.first { $0.id == language.id }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(language.name, systemImage: runtime?.available == true ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(runtime?.available == true ? accent : .secondary).fontWeight(.medium)
                                Spacer()
                                Button("Choose executable…") { model.chooseRuntime(language) }
                                if model.overrides[language.id] != nil { Button("Reset") { model.clearRuntime(language) } }
                            }
                            Text(runtime?.version ?? "Checking…").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if runtime?.available != true {
                                Text(language.installCommand).font(.caption.monospaced()).textSelection(.enabled)
                            }
                            if !language.note.isEmpty { Text(language.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Divider()
                    }
                }
            }
            HStack {
                Text("Installation commands are suggestions; nothing is installed automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isDiscovering)
            }
        }.padding(24).frame(width: 750, height: 650)
    }
}

struct ResultDetail: View {
    let result: BenchmarkResult
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = ContentState()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(result.language).font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Text(result.runtimeVersion).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 28) {
                VStack(alignment: .leading) { Text("Iterations").font(.caption); Text(String(result.samplesNS.count)).font(.title2) }
                VStack(alignment: .leading) { Text("Mean").font(.caption); Text(TimeDisplay.format(result.meanNS)).font(.title2).foregroundStyle(accent) }
                VStack(alignment: .leading) { Text("Median").font(.caption); Text(TimeDisplay.format(result.medianNS)).font(.title2).foregroundStyle(accent) }
                VStack(alignment: .leading) { Text("Compilation").font(.caption); Text(String(format: "%.3f s", result.compilationSeconds)).font(.title2) }
            }
            Text("Measured iterations · warm-ups excluded").fontWeight(.semibold)
            Text("Mean is the average; median is the middle value after sorting. Rankings use median.").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading) {
                ForEach(Array(result.samplesNS.enumerated()), id: \.offset) { sample in
                    Text("\(sample.offset + 1). \(TimeDisplay.format(sample.element))").font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            if let language = Language.all.first(where: { $0.id == result.id }) {
                if !language.note.isEmpty { Text(language.note).font(.callout).foregroundStyle(.secondary) }
                Button("Explore prime-calculation code") { ui.showCode = true }
            }
            Text("Build / launch configuration").fontWeight(.semibold)
            Text(result.command.joined(separator: " ")).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Text("Executable: \(result.executablePath)").font(.caption).textSelection(.enabled)
            if let command = result.launchCommand {
                Text("Worker launch: \(command.joined(separator: " "))").font(.caption.monospaced()).textSelection(.enabled)
            }
            ForEach(Array((result.helperTools ?? []).enumerated()), id: \.offset) { entry in
                Text("\(entry.element.role): \(entry.element.version)\n\(entry.element.executablePath)")
                    .font(.caption).textSelection(.enabled)
            }
            Text("Source SHA-256: \(result.sourceHash)").font(.caption.monospaced()).textSelection(.enabled)
            if let files = result.sourceFiles {
                Text("Hashed inputs (format \(result.sourceHashFormat ?? 2)): \(files.joined(separator: ", "))")
                    .font(.caption).textSelection(.enabled)
            }
            }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(width: 750, height: 520).tint(accent)
        .sheet(isPresented: $ui.showCode) { CodeExplorerView(initialLanguageID: result.id) }
    }
}
