import SwiftUI
import AppKit
import PrimeSieveCore

/// Holds navigation separately from benchmark state, so exploring code never changes the run selection.
@MainActor
private final class ExplorerState: ObservableObject {
    @Published var languageID: String
    @Published var search = ""
    @Published var architecture = BenchmarkSession.architecture
    @Published var fontSize = 13.0
    @Published var sections: [PrimeCodeSection] = []
    @Published var error: String?

    init(languageID: String) { self.languageID = languageID }
    var implementation: SieveImplementation { SieveImplementation.all.first { $0.id == languageID } ?? SieveImplementation.all[0] }
    var language: Language { implementation.language }
    func load() {
        do {
            try SieveImplementation.validateRegistry()
            sections = try PrimeCodeExplorer.sections(for: implementation, architecture: architecture); error = nil
        }
        catch { sections = []; self.error = error.localizedDescription }
    }
}

/// A read-only, selectable view of the documented calculation regions in the bundled worker files.
struct CodeExplorerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: ExplorerState

    init(initialLanguageID: String = "swift") {
        _state = StateObject(wrappedValue: ExplorerState(languageID: initialLanguageID))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Code explorer", systemImage: "chevron.left.forwardslash.chevron.right").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Find a language", text: $state.search).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(SieveImplementation.all.sorted { ($0.language.name + $0.name) < ($1.language.name + $1.name) }.filter {
                                state.search.isEmpty || $0.name.localizedCaseInsensitiveContains(state.search) || $0.language.name.localizedCaseInsensitiveContains(state.search)
                            }) { language in
                                Button { state.languageID = language.id } label: {
                                    HStack {
                                        Text("\(language.language.name) · \(language.name)")
                                        Spacer()
                                        if state.languageID == language.id { Image(systemName: "chevron.right") }
                                    }.padding(9).contentShape(Rectangle())
                                    .background(state.languageID == language.id ? accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                                .accessibilityAddTraits(state.languageID == language.id ? .isSelected : [])
                            }
                        }
                    }
                    Text("All 35 languages are available to explore, even without an installed runtime.").font(.caption).foregroundStyle(.secondary)
                }.padding(16).frame(width: 240)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("\(state.language.name) · \(state.implementation.name)").font(.title2.weight(.semibold)).foregroundStyle(accent)
                        Spacer()
                        Stepper("Text \(Int(state.fontSize)) pt", value: $state.fontSize, in: 11...20).fixedSize()
                        Button("Copy code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.sections.map(\.code).joined(separator: "\n\n"), forType: .string)
                        }.disabled(state.sections.isEmpty)
                    }
                    if state.language.id == "assembly" {
                        Picker("Architecture", selection: $state.architecture) {
                            Text("Apple Silicon · ARM64").tag("arm64")
                            Text("Intel · x86-64").tag("x86_64")
                        }.pickerStyle(.segmented)
                    }
                    Text("Actual bundled calculation code. n is the requested count; limit is inclusive. Throughput times allocation and marking; result scanning follows the window.")
                        .font(.callout).foregroundStyle(.secondary)
                    if !state.implementation.explanation.isEmpty { Text(state.implementation.explanation).font(.caption).foregroundStyle(.secondary) }
                    if let error = state.error {
                        Text(error).foregroundStyle(.red)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(state.sections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(section.title).font(.headline)
                                        Spacer()
                                        Text("Line \(section.sourceLine)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    ScrollView(.horizontal) {
                                        Text(section.code).font(.system(size: state.fontSize, design: .monospaced))
                                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }.padding(.bottom, 16)
                    }.id("\(state.languageID)-\(state.architecture)")
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.frame(width: 1050, height: 720).tint(accent)
        .onAppear { state.load() }
        .onChange(of: state.languageID) { _, _ in state.load() }
        .onChange(of: state.architecture) { _, _ in state.load() }
    }
}
