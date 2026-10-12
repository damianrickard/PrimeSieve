import Foundation

public enum SessionStore {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrimeSieve/Sessions")
    }
    public static func save(_ session: BenchmarkSession) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json(session).write(to: directory.appendingPathComponent("\(session.id).json"), options: .atomic)
    }
    public static func load() -> [BenchmarkSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(BenchmarkSession.self, from: data)
        }.sorted { $0.date > $1.date }
    }
    public static func json(_ session: BenchmarkSession) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Derived statistics accompany the raw samples. Older sessions remain decodable because
        // BenchmarkResult derives its statistics from samples and ignores additional JSON keys.
        let encoded = try encoder.encode(session)
        guard var document = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var results = document["results"] as? [[String: Any]], results.count == session.results.count else {
            throw BenchmarkError.message("Unable to encode benchmark statistics.")
        }
        for index in session.results.indices {
            let result = session.results[index]
            results[index]["meanNS"] = result.meanNS
            results[index]["medianNS"] = result.medianNS
            results[index]["iterations"] = result.samplesNS.count
        }
        document["results"] = results
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }
    public static func csv(_ session: BenchmarkSession) -> String {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["rank,language,prime_count,timing_mode,iterations,mean_ns,median_ns,minimum_ns,maximum_ns,samples_ns,last_prime,checksum,runtime,compiler_command,source_sha256,machine,date,executable_path,helper_tools,worker_launch,source_files,source_hash_format"]
        for (index, result) in session.results.sorted(by: { $0.medianNS < $1.medianNS }).enumerated() {
            let helpers = (result.helperTools ?? []).map { "\($0.role): \($0.executablePath) [\($0.version)]" }.joined(separator: "; ")
            let samples = result.samplesNS.map { String($0) }.joined(separator: ";")
            let format = result.sourceHashFormat.map { String($0) } ?? "legacy"
            let cells: [String] = [String(index+1), result.language, String(session.configuration.primeCount), session.configuration.mode.rawValue,
                         String(result.samplesNS.count), String(result.meanNS), String(result.medianNS), String(result.minimumNS), String(result.maximumNS), samples,
                         String(result.signature.lastPrime), String(result.signature.checksum), result.runtimeVersion,
                         result.command.joined(separator: " "), result.sourceHash, session.machine, ISO8601DateFormatter().string(from: session.date),
                         result.executablePath,
                         helpers,
                         (result.launchCommand ?? []).joined(separator: " "), (result.sourceFiles ?? []).joined(separator: ";"),
                         format]
            lines.append(cells.map(quote).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
