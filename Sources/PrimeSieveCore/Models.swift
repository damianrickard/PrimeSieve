import Foundation

public enum TimingMode: String, Codable, CaseIterable, Sendable {
    case calculation = "Calculation"
    case startup = "Startup + calculation"
    case throughput = "Sieve throughput"
}

public enum Workload: String, Codable, CaseIterable, Sendable {
    case firstN = "First N primes"
    case upperLimit = "Primes up to limit"
}
public enum ImplementationSelection: String, Codable, CaseIterable, Sendable {
    case baseline = "Baselines"
    case candidates = "Tuned variants"
    case all = "Baselines + variants"
}

public struct BenchmarkConfiguration: Codable, Sendable {
    public var primeCount: Int
    public var repetitions: Int
    public var warmups: Int
    public var timeoutSeconds: Double
    public var mode: TimingMode
    public var workload: Workload
    public var upperLimit: Int
    public var durationSeconds: Double
    public var rounds: Int
    public var implementations: ImplementationSelection
    public var implementationIDs: [String]?
    public var contractVersion: Int

    public init(primeCount: Int = 100_000, repetitions: Int = 7, warmups: Int = 3,
                timeoutSeconds: Double = 120, mode: TimingMode = .calculation,
                workload: Workload = .firstN, upperLimit: Int = 1_000_000,
                durationSeconds: Double = 5, rounds: Int = 1,
                implementations: ImplementationSelection = .baseline, implementationIDs: [String]? = nil) {
        self.primeCount = primeCount; self.repetitions = repetitions; self.warmups = warmups
        self.timeoutSeconds = timeoutSeconds; self.mode = mode; self.workload = workload
        self.upperLimit = upperLimit; self.durationSeconds = durationSeconds; self.rounds = rounds
        self.implementations = implementations; self.implementationIDs = implementationIDs; contractVersion = 3
    }
    enum CodingKeys: String, CodingKey {
        case primeCount, repetitions, warmups, timeoutSeconds, mode, workload, upperLimit
        case durationSeconds, rounds, implementations, implementationIDs, contractVersion
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primeCount = try c.decode(Int.self, forKey: .primeCount)
        repetitions = try c.decode(Int.self, forKey: .repetitions)
        warmups = try c.decode(Int.self, forKey: .warmups)
        timeoutSeconds = try c.decode(Double.self, forKey: .timeoutSeconds)
        mode = try c.decode(TimingMode.self, forKey: .mode)
        workload = try c.decodeIfPresent(Workload.self, forKey: .workload) ?? .firstN
        upperLimit = try c.decodeIfPresent(Int.self, forKey: .upperLimit) ?? 1_000_000
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 5
        rounds = try c.decodeIfPresent(Int.self, forKey: .rounds) ?? 1
        implementations = try c.decodeIfPresent(ImplementationSelection.self, forKey: .implementations) ?? .baseline
        implementationIDs = try c.decodeIfPresent([String].self, forKey: .implementationIDs)
        contractVersion = try c.decodeIfPresent(Int.self, forKey: .contractVersion) ?? 1
    }
    public func validate() throws {
        if workload == .firstN && !(1...10_000_000).contains(primeCount) {
            throw BenchmarkError.message("Use a prime count of 1–10,000,000.")
        }
        if workload == .upperLimit && !(2...200_000_000).contains(upperLimit) {
            throw BenchmarkError.message("Use an inclusive upper limit of 2–200,000,000.")
        }
        guard (1...30).contains(repetitions), (0...20).contains(warmups), (1...10).contains(rounds),
              timeoutSeconds.isFinite, (1...3600).contains(timeoutSeconds),
              durationSeconds.isFinite, (0.01...60).contains(durationSeconds) else {
            throw BenchmarkError.message("Use 1–30 samples, 0–20 warm-ups, 1–10 rounds, 0.01–60 seconds/window, and a 1–3,600 second timeout.")
        }
        if mode == .throughput {
            guard workload == .upperLimit, timeoutSeconds > durationSeconds * Double(repetitions) else {
                throw BenchmarkError.message("Sieve throughput requires an upper limit and a timeout longer than all measured windows in a round. Allow additional time for startup, warm-ups, final-pass overrun, verification and output.")
            }
        }
    }
    /// A planning suggestion, not a bound on runtime-dependent work outside the windows.
    public var suggestedThroughputTimeout: Double { max(30, 2 * durationSeconds * Double(repetitions)) }
    public var timeoutGuidance: String? {
        guard mode == .throughput else { return nil }
        return "The timeout covers the entire worker round: startup, warm-ups, measured windows, final-pass overrun, verification and output. Start with at least \(suggestedThroughputTimeout.formatted()) seconds (twice the requested window time, with a 30-second minimum); slow runtimes or large limits may need more. This is a planning suggestion, not a completion guarantee."
    }
    public var sieveLimit: Int {
        if workload == .upperLimit { return upperLimit }
        if primeCount < 6 { return 15 }
        let n = Double(primeCount)
        return Int(ceil(n * (log(n) + log(log(n))))) + 16
    }
    public var workloadDescription: String {
        workload == .firstN ? "First \(primeCount.formatted()) primes" : "Primes ≤ \(upperLimit.formatted())"
    }
    public static var dragRace: Self {
        .init(repetitions: 1, warmups: 3, mode: .throughput, workload: .upperLimit,
              durationSeconds: 5, rounds: 3, implementations: .candidates)
    }
    public var measurementContract: String {
        if mode == .throughput { return "v3: fresh allocation + sieve + per-pass observation + prior-buffer release; retained final sieve verified after each wall-clock window; scan excluded" }
        return "v\(contractVersion): allocation + initialization + sieve + result scan; checksum/output excluded from calculation; startup includes the entire worker"
    }
}

public enum BenchmarkError: Error, LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

public struct PrimeSignature: Codable, Equatable, Sendable {
    public var count: Int
    public var lastPrime: Int
    public var checksum: Int
    public init(count: Int, lastPrime: Int, checksum: Int) {
        self.count = count; self.lastPrime = lastPrime; self.checksum = checksum
    }
}

public struct WorkerSample: Codable, Sendable {
    public var elapsedNS: Double
    public var count: Int
    public var lastPrime: Int
    public var checksum: Int
    public var passes: Int?
    public var primes: [Int]?
    enum CodingKeys: String, CodingKey {
        case elapsedNS = "elapsed_ns", count, lastPrime = "last_prime", checksum, passes, primes
    }
    public var signature: PrimeSignature { .init(count: count, lastPrime: lastPrime, checksum: checksum) }
}

public struct RuntimeStatus: Identifiable, Sendable {
    public let language: Language
    public let executable: URL?
    public let version: String
    public var id: String { language.id }
    public var available: Bool { executable != nil }
    public init(language: Language, executable: URL?, version: String) {
        self.language = language; self.executable = executable; self.version = version
    }
}

public struct ToolRecord: Codable, Sendable {
    public var role: String
    public var executablePath: String
    public var version: String
}

public struct BenchmarkResult: Codable, Identifiable, Sendable {
    public var id: String
    public var language: String
    public var runtimeVersion: String
    public var executablePath: String
    public var samplesNS: [Double]
    public var compilationSeconds: Double
    public var signature: PrimeSignature
    public var command: [String]
    public var sourceHash: String
    // Optional additions keep historical sessions readable without inventing missing provenance.
    public var helperTools: [ToolRecord]? = nil
    public var launchCommand: [String]? = nil
    public var sourceFiles: [String]? = nil
    public var sourceHashFormat: Int? = nil
    public var implementation: SieveImplementation? = nil
    public var windows: [MeasurementWindow]? = nil
    public var roundOrders: [Int]? = nil
    public var contract: String? = nil
    public var isThroughput: Bool { windows?.isEmpty == false }
    public var displayName: String { implementation.map { "\(language) · \($0.name)" } ?? language }
    public var score: Double { isThroughput ? Statistics.median(windows!.map(\.passesPerSecond)) : medianNS }
    public var meanScoreDisplay: String { isThroughput ? String(format: "%.1f/s", (windows ?? []).map(\.passesPerSecond).reduce(0,+) / Double(max(1, windows?.count ?? 0))) : TimeDisplay.format(meanNS) }
    public var slowestScoreDisplay: String { isThroughput ? String(format: "%.1f/s", (windows ?? []).map(\.passesPerSecond).min() ?? 0) : TimeDisplay.format(maximumNS) }
    public var scoreDisplay: String { isThroughput ? String(format: "%.1f passes/s", score) : TimeDisplay.format(score) }
    public var interquartileRange: Double { Statistics.iqr(isThroughput ? windows!.map(\.passesPerSecond) : samplesNS) }
    public static func faster(_ a: Self, _ b: Self) -> Bool { a.isThroughput ? a.score > b.score : a.score < b.score }
    /// Arithmetic mean of measured iterations; warm-up runs are never stored as samples.
    public var meanNS: Double {
        guard !samplesNS.isEmpty else { return 0 }
        return samplesNS.reduce(0) { $0 + $1 / Double(samplesNS.count) }
    }
    public var medianNS: Double {
        let sorted = samplesNS.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
    public var minimumNS: Double { samplesNS.min() ?? 0 }
    public var maximumNS: Double { samplesNS.max() ?? 0 }
}

public struct BenchmarkSession: Codable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var configuration: BenchmarkConfiguration
    public var machine: String
    public var results: [BenchmarkResult]
    public var failures: [String: String]
    public var completed: Bool
    public var machineDetails: MachineDetails? = nil
    public var executionOrder: [[String]]? = nil
    public init(configuration: BenchmarkConfiguration) {
        id = UUID(); date = Date(); self.configuration = configuration
        machine = "\(ProcessInfo.processInfo.hostName) • \(ProcessInfo.processInfo.operatingSystemVersionString) • \(Self.architecture)"
        results = []; failures = [:]; completed = false; machineDetails = MachineDetails.capture(); executionOrder = []
    }
    public static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

public enum TimeDisplay {
    public static func format(_ nanoseconds: Double) -> String {
        if nanoseconds < 1_000 { return String(format: "%.1f ns", nanoseconds) }
        if nanoseconds < 1_000_000 { return String(format: "%.2f µs", nanoseconds / 1_000) }
        if nanoseconds < 1_000_000_000 { return String(format: "%.2f ms", nanoseconds / 1_000_000) }
        return String(format: "%.3f s", nanoseconds / 1_000_000_000)
    }
}

public struct MeasurementWindow: Codable, Sendable {
    public var passes: Int
    public var elapsedNS: Double
    public var threads: Int = 1
    public var passesPerSecond: Double { Double(passes) * 1e9 / elapsedNS }
    public var passesPerSecondPerThread: Double { passesPerSecond / Double(threads) }
    public init(passes: Int, elapsedNS: Double, threads: Int = 1) { self.passes = passes; self.elapsedNS = elapsedNS; self.threads = threads }
    enum CodingKeys: String, CodingKey { case passes, elapsedNS, threads, passesPerSecond, passesPerSecondPerThread }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passes = try c.decode(Int.self, forKey: .passes); elapsedNS = try c.decode(Double.self, forKey: .elapsedNS)
        threads = try c.decode(Int.self, forKey: .threads)
        guard passes > 0, elapsedNS.isFinite, elapsedNS > 0, threads > 0 else { throw BenchmarkError.message("Invalid saved throughput window.") }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(passes, forKey: .passes); try c.encode(elapsedNS, forKey: .elapsedNS); try c.encode(threads, forKey: .threads)
        try c.encode(passesPerSecond, forKey: .passesPerSecond); try c.encode(passesPerSecondPerThread, forKey: .passesPerSecondPerThread)
    }

}
public enum Statistics {
    public static func median(_ values: [Double]) -> Double { quantile(values, 0.5) }
    public static func quantile(_ values: [Double], _ q: Double) -> Double {
        let a = values.sorted(); guard !a.isEmpty else { return 0 }
        let position = Double(a.count - 1) * q, lower = Int(position)
        return a[lower] + (a[min(lower + 1, a.count - 1)] - a[lower]) * (position - Double(lower))
    }
    public static func iqr(_ values: [Double]) -> Double { quantile(values, 0.75) - quantile(values, 0.25) }
}
