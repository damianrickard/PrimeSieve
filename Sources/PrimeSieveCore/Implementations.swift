import Foundation

/// Stored in results as a snapshot, so later registry edits cannot relabel old runs.
public struct SieveImplementation: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var languageID: String
    public var name: String
    public var source: String
    public var variant: String
    public var algorithm: String
    public var bits: Int?
    public var storage: String
    public var dependencies: String
    public var allocation: String
    public var threadModel: String
    public var architectures: [String]
    public var explanation: String
    public var protocolVersion: Int
    public var provenance: String
    public var isBaseline: Bool { protocolVersion == 1 }
    public var supportsThroughput: Bool { protocolVersion >= 3 }
    public var summary: String { "\(algorithm) · \(storage) · \(threadModel) · \(dependencies)" }
    public var language: Language { Language.all.first { $0.id == languageID }! }
    public var sourceURL: URL { language.sourceURL.deletingLastPathComponent().appendingPathComponent(source) }
    public func files(architecture: String = BenchmarkSession.architecture) -> [String] {
        if isBaseline { return WorkerSources.names(for: language, architecture: architecture) }
        if languageID == "assembly" { return [source, "tuned_\(architecture).s"] }
        if languageID == "r" { return [source, "clock.c"] }
        return [source]
    }
    private static let baselines: [Self] = Language.all.map { language in
            let indirect = ["lua", "elixir", "erlang"].contains(language.id)
            return Self(id: language.id, languageID: language.id,
                        name: language.id == "assembly" ? "Assembly kernel with C harness · baseline" : "Baseline",
                        source: language.source, variant: "baseline", algorithm: "Odd-only Eratosthenes",
                        bits: indirect ? nil : 8, storage: indirect ? "Runtime container; flag size unknown" : "Byte flags",
                        dependencies: language.id == "assembly" ? "C allocation/timing/output harness" : "No external sieve library",
                        allocation: "Fresh candidate storage per pass", threadModel: "Single sieve thread",
                        architectures: ["arm64", "x86_64"], explanation: language.note.isEmpty ? "Original common-loop implementation. Calculation includes scanning to the requested result." : language.note,
                        protocolVersion: 1, provenance: "PrimeSieve original baseline; exact source hash recorded")
    }
    // Cache both success and failure. UI reads never repeat filesystem access or decoding.
    private static let bundledVariants: Result<[Self], BenchmarkError> = {
        let url = Language.all[0].sourceURL.deletingLastPathComponent().appendingPathComponent("implementations.json")
        return loadVariants(from: url)
    }()
    // Keep baseline descriptions available to the UI even if the bundle is damaged.
    // The visible registry error and validation gate prevent incomplete benchmark runs.
    public static let all: [Self] = baselines + ((try? bundledVariants.get()) ?? [])
    public static var registryError: String? {
        if case .failure(let error) = bundledVariants { return error.localizedDescription }
        return nil
    }
    public static func validateRegistry() throws { _ = try bundledVariants.get() }

    static func loadVariants(from url: URL) -> Result<[Self], BenchmarkError> {
        do {
            let variants = try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
            let languageIDs = Set(Language.all.map(\.id))
            let ids = (baselines + variants).map(\.id)
            guard !variants.isEmpty, Set(ids).count == ids.count,
                  variants.allSatisfy({ languageIDs.contains($0.languageID) && !$0.isBaseline }) else {
                throw BenchmarkError.message("Expected nonempty variants with unique IDs and known languages.")
            }
            return .success(variants)
        } catch {
            return .failure(.message("Unable to load implementation registry (\(url.lastPathComponent)): \(error.localizedDescription)"))
        }
    }
    public static func selected(for languageID: String, configuration: BenchmarkConfiguration) -> [Self] {
        all.filter { implementation in
            guard implementation.languageID == languageID else { return false }
            if let ids = configuration.implementationIDs { return ids.contains(implementation.id) }
            switch configuration.implementations {
            case .baseline: return implementation.isBaseline
            case .candidates: return !implementation.isBaseline
            case .all: return true
            }
        }
    }
}
