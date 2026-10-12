import XCTest
import Darwin
@testable import PrimeSieveCore

final class BenchmarkTests: XCTestCase {
    func testExplorerShowsDocumentedCalculationForEveryLanguage() throws {
        for language in Language.all {
            for architecture in language.id == "assembly" ? ["arm64", "x86_64"] : [BenchmarkSession.architecture] {
                let sections = try PrimeCodeExplorer.sections(for: language, architecture: architecture)
                XCTAssertGreaterThanOrEqual(sections.count, 3, language.name)
                XCTAssertTrue(sections.contains { $0.title == "Mark composites" }, language.name)
                XCTAssertTrue(sections.contains { $0.title == "Find the Nth prime" }, language.name)
                for section in sections {
                    XCTAssertGreaterThan(section.sourceLine, 1)
                    XCTAssertFalse(section.code.contains("elapsed_ns"), "Output leaked into \(language.name)")
                    XCTAssertFalse(section.code.contains("PRIME-"))
                    XCTAssertGreaterThan(section.code.components(separatedBy: "\n").count, 1)
                }
            }
        }
        XCTAssertThrowsError(try PrimeCodeExplorer.parse("// PRIME-BEGIN: Incomplete\ncode"))
        XCTAssertThrowsError(try PrimeCodeExplorer.parse("// PRIME-END"))
        XCTAssertThrowsError(try PrimeCodeExplorer.parse("// PRIME-BEGIN: A\n// PRIME-BEGIN: B\ncode\n// PRIME-END"))
    }

    func testMeanMedianAndExportsPreserveMeasuredIterations() throws {
        var result = BenchmarkResult(id: "swift", language: "Swift", runtimeVersion: "Test",
            executablePath: "/usr/bin/swiftc", samplesNS: [10, 100, 20], compilationSeconds: 0,
            signature: .init(count: 1, lastPrime: 2, checksum: 2), command: [], sourceHash: "test")
        XCTAssertEqual(result.meanNS, 130.0 / 3.0, accuracy: 0.000001)
        XCTAssertEqual(result.medianNS, 20)
        result.samplesNS = [40, 10, 20, 30]
        XCTAssertEqual(result.meanNS, 25)
        XCTAssertEqual(result.medianNS, 25)
        var session = BenchmarkSession(configuration: .init(primeCount: 1, repetitions: 4))
        session.results = [result]
        let json = try SessionStore.json(session)
        let roundTrip = try JSONDecoder().decode(BenchmarkSession.self, from: json)
        XCTAssertEqual(roundTrip.results[0].samplesNS, result.samplesNS)
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let rows = try XCTUnwrap(exported["results"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["iterations"] as? Int, 4)
        XCTAssertEqual(rows[0]["meanNS"] as? Double, 25)
        XCTAssertEqual(rows[0]["medianNS"] as? Double, 25)
        XCTAssertTrue(SessionStore.csv(session).contains("iterations,mean_ns,median_ns"))
        // Historical JSON without derived statistics must remain readable.
        let oldJSON = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(BenchmarkSession.self, from: oldJSON).results[0].meanNS, 25)
        result.samplesNS = [12]
        XCTAssertEqual(result.meanNS, 12)
        XCTAssertEqual(result.medianNS, 12)
        result.samplesNS = []
        XCTAssertEqual(result.meanNS, 0)
        XCTAssertEqual(result.medianNS, 0)
    }

    func testRosterAndEverySourceExists() throws {
        XCTAssertEqual(Language.all.count, 35)
        XCTAssertEqual(Set(Language.all.map(\.id)).count, 35)
        let required = Set(["assembly", "csharp", "java", "cpp", "swift", "c", "rust", "lisp", "pascal"])
        XCTAssertTrue(required.isSubset(of: Set(Language.all.map(\.id))))
        for language in Language.all {
            XCTAssertTrue(FileManager.default.fileExists(atPath: language.sourceURL.path), language.name)
            XCTAssertFalse(try Data(contentsOf: language.sourceURL).isEmpty, language.name)
        }
    }

    func testReferenceAgainstKnownPrimesAndSums() throws {
        for (count, last, checksum) in [(1,2,2), (2,3,5), (5,11,28), (10,29,129), (100,541,24133), (1000,7919,3682913)] {
            let config = BenchmarkConfiguration(primeCount: count)
            XCTAssertEqual(try PrimeReference.signature(count: count, limit: config.sieveLimit),
                           PrimeSignature(count: count, lastPrime: last, checksum: checksum))
        }
    }

    func testConfigurationRejectsDangerousAndInvalidInputs() {
        for count in [0,-1,10_000_001,Int.max] {
            XCTAssertThrowsError(try BenchmarkConfiguration(primeCount: count).validate())
        }
        XCTAssertThrowsError(try BenchmarkConfiguration(repetitions: 0).validate())
        XCTAssertThrowsError(try BenchmarkConfiguration(warmups: -1).validate())
        XCTAssertThrowsError(try BenchmarkConfiguration(timeoutSeconds: .nan).validate())
    }

    func testIncorrectOrIncompleteWorkersCannotEnterRankings() throws {
        let reference = PrimeSignature(count: 10, lastPrime: 29, checksum: 129)
        let good = "{\"elapsed_ns\":12,\"count\":10,\"last_prime\":29,\"checksum\":129}"
        XCTAssertEqual(try BenchmarkRunner.decode("compiler noise\n"+good, expectedSamples: 1, reference: reference).count, 1)
        for bad in [good.replacingOccurrences(of: "29", with: "31"), good.replacingOccurrences(of: "129", with: "0"), good.replacingOccurrences(of: ":12", with: ":-12"), "{}", ""] {
            XCTAssertThrowsError(try BenchmarkRunner.decode(bad, expectedSamples: 1, reference: reference))
        }
        XCTAssertThrowsError(try BenchmarkRunner.decode(good, expectedSamples: 2, reference: reference))
    }

    func testSubprocessTimeoutAndCancellation() async throws {
        let sleeper = URL(fileURLWithPath: "/bin/sleep")
        do {
            _ = try await ProcessExecutor.run(executable: sleeper, arguments: ["5"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Timed out")) }
        let task = Task { try await ProcessExecutor.run(executable: sleeper, arguments: ["5"], timeout: 10) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testArgumentsArePassedLiterallyWithoutShellExpansion() async throws {
        let literal = "$(touch /tmp/primesieve-injected); `whoami`"
        let output = try await ProcessExecutor.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: [literal])
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .newlines), literal)
    }

    func testAvailableWorkersAtEdgeCasesAndNontrivialCount() async throws {
        let statuses = await RuntimeDiscovery.discover().filter(\.available)
        if ProcessInfo.processInfo.environment["PRIMESIEVE_REQUIRE_ALL"] == "1" { XCTAssertEqual(statuses.count, 35) }
        XCTAssertTrue(statuses.contains { $0.id == "swift" })
        for count in [1,2,5,1000] {
            let config = BenchmarkConfiguration(primeCount: count, repetitions: 2, warmups: 1)
            let session = try await BenchmarkRunner.run(statuses: statuses, configuration: config)
            XCTAssertTrue(session.failures.isEmpty, String(describing: session.failures))
            XCTAssertEqual(session.results.count, statuses.count)
            XCTAssertTrue(session.results.allSatisfy { $0.samplesNS.count == 2 })
        }
    }

    func testAllInstalledWorkers() async throws {
        let statuses = await RuntimeDiscovery.discover().filter(\.available)
        if ProcessInfo.processInfo.environment["PRIMESIEVE_REQUIRE_ALL"] == "1" { XCTAssertEqual(statuses.count, 35) }
        let session = try await BenchmarkRunner.run(statuses: statuses,
            configuration: BenchmarkConfiguration(primeCount: 10_000, repetitions: 3, warmups: 2, timeoutSeconds: 180))
        XCTAssertTrue(session.failures.isEmpty, String(describing: session.failures))
        XCTAssertEqual(session.results.count, statuses.count)
        XCTAssertTrue(session.results.allSatisfy { $0.signature.lastPrime == 104_729 && $0.signature.checksum == 496_165_411 })
        for result in session.results {
            XCTAssertEqual(result.sourceHashFormat, 2)
            XCTAssertFalse(result.sourceFiles?.isEmpty ?? true)
            if result.id == "scheme" {
                XCTAssertTrue(result.launchCommand?.joined(separator: " ").contains("load-compiled") ?? false)
                XCTAssertGreaterThan(result.compilationSeconds, 0)
            }
            if ["csharp", "fsharp"].contains(result.id) {
                XCTAssertTrue(result.sourceFiles?.contains(where: { $0.hasSuffix("proj") }) ?? false)
            }
        }
        if let path = ProcessInfo.processInfo.environment["PRIMESIEVE_VALIDATION_OUTPUT"] {
            try SessionStore.json(session).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    func testCancellationAlsoStopsChildProcesses() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("PrimeSieve-child-\(UUID()).pid")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let task = Task {
            try await ProcessExecutor.run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "/bin/sleep 10 & child=$!; printf '%s' \"$child\" > \"$1\"; wait", "sh", pidFile.path], timeout: 20)
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard let pid = Int32(try String(contentsOf: pidFile)) else { XCTFail("Missing child PID"); task.cancel(); return }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<100 where Darwin.kill(pid, 0) == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotEqual(Darwin.kill(pid, 0), 0, "The worker's descendant must stop too")
    }
}
