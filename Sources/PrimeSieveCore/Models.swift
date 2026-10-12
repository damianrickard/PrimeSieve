import Foundation

public enum TimingMode: String, Codable, CaseIterable, Sendable {
    case calculation = "Calculation"
    case startup = "Startup + calculation"
}

public struct BenchmarkConfiguration: Codable, Sendable {
    public var primeCount: Int
    public var repetitions: Int
    public var warmups: Int
    public var timeoutSeconds: Double
    public var mode: TimingMode

    public init(primeCount: Int = 100_000, repetitions: Int = 7, warmups: Int = 3,
                timeoutSeconds: Double = 120, mode: TimingMode = .calculation) {
        self.primeCount = primeCount
        self.repetitions = repetitions
        self.warmups = warmups
        self.timeoutSeconds = timeoutSeconds
        self.mode = mode
    }

    public func validate() throws {
        guard (1...10_000_000).contains(primeCount) else {
            throw BenchmarkError.message("Enter a prime count between 1 and 10,000,000.")
        }
        guard (1...30).contains(repetitions), (0...20).contains(warmups),
              timeoutSeconds.isFinite, (1...3600).contains(timeoutSeconds) else {
            throw BenchmarkError.message("Repetitions must be 1–30, warm-ups 0–20, and timeout 1–3,600 seconds.")
        }
    }

    /// A common conservative upper bound, computed outside every language's timed region.
    public var sieveLimit: Int {
        if primeCount < 6 { return 15 }
        let n = Double(primeCount)
        return Int(ceil(n * (log(n) + log(log(n))))) + 16
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
    enum CodingKeys: String, CodingKey {
        case elapsedNS = "elapsed_ns", count, lastPrime = "last_prime", checksum
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
    public init(configuration: BenchmarkConfiguration) {
        id = UUID(); date = Date(); self.configuration = configuration
        machine = "\(ProcessInfo.processInfo.hostName) • \(ProcessInfo.processInfo.operatingSystemVersionString) • \(Self.architecture)"
        results = []; failures = [:]; completed = false
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
