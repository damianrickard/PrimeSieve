import XCTest
@testable import PrimeSieveCore

final class VariantTests: XCTestCase {
    func testOnlyActiveWorkloadValueIsValidated() throws {
        try BenchmarkConfiguration(primeCount: 100, upperLimit: 0).validate()
        try BenchmarkConfiguration(primeCount: 0, workload: .upperLimit, upperLimit: 1024).validate()
        XCTAssertThrowsError(try BenchmarkConfiguration(primeCount: 0).validate())
        XCTAssertThrowsError(try BenchmarkConfiguration(workload: .upperLimit, upperLimit: 0).validate())
    }
    func testThroughputTimeoutExplainsOverheadWithoutChangingUserBudget() throws {
        var config = BenchmarkConfiguration(repetitions: 23, warmups: 3, timeoutSeconds: 120,
            mode: .throughput, workload: .upperLimit, upperLimit: 200_000_000, durationSeconds: 5)
        try config.validate()
        XCTAssertEqual(config.timeoutSeconds, 120)
        XCTAssertEqual(config.suggestedThroughputTimeout, 230)
        let guidance = try XCTUnwrap(config.timeoutGuidance)
        for term in ["startup", "warm-ups", "final-pass overrun", "verification", "output", "not a completion guarantee"] {
            XCTAssertTrue(guidance.contains(term))
        }
        config.timeoutSeconds = 115
        XCTAssertThrowsError(try config.validate())
        XCTAssertEqual(BenchmarkConfiguration.dragRace.suggestedThroughputTimeout, 30)
        XCTAssertNil(BenchmarkConfiguration().timeoutGuidance)
    }
    func testMalformedWorkerOutputIncludesBoundedDiagnostic() {
        let reference = PrimeSignature(count: 1, lastPrime: 2, checksum: 2)
        for line in ["{broken", "{}", "{\"elapsed_ns\":\"bad\"}", "{" + String(repeating: "x", count: 400)] {
            XCTAssertThrowsError(try BenchmarkRunner.decode(line, expectedSamples: 1, reference: reference)) { error in
                XCTAssertEqual(error.localizedDescription, "Worker returned malformed timing data: \(line.prefix(180))")
            }
        }
    }
    func testRegistryReportsMissingMalformedAndInvalidVariants() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("implementations.json")
        func assertFailure() {
            XCTAssertThrowsError(try SieveImplementation.loadVariants(from: url).get()) { error in
                XCTAssertTrue(error.localizedDescription.hasPrefix("Unable to load implementation registry (implementations.json):"))
            }
        }
        assertFailure() // Missing file.
        for text in ["{broken", "null", "[]"] {
            try Data(text.utf8).write(to: url)
            assertFailure()
        }
        var variant = try XCTUnwrap(SieveImplementation.all.first { !$0.isBaseline })
        try JSONEncoder().encode([variant, variant]).write(to: url)
        assertFailure() // Duplicate IDs.
        variant.languageID = "unknown-language"
        try JSONEncoder().encode([variant]).write(to: url)
        assertFailure() // Cannot resolve a language for the UI or runner.
        try SieveImplementation.validateRegistry()
        XCTAssertNil(SieveImplementation.registryError)
    }
    func testLegacyConfigurationAndResultRemainExplicitlyLegacy() throws {
        let json = #"{"primeCount":1000,"repetitions":3,"warmups":1,"timeoutSeconds":120,"mode":"Calculation"}"#
        let config = try JSONDecoder().decode(BenchmarkConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(config.contractVersion, 1)
        XCTAssertEqual(config.workload, .firstN)
        XCTAssertEqual(config.rounds, 1)
        XCTAssertEqual(config.implementations, .baseline)
        XCTAssertEqual(BenchmarkConfiguration.dragRace.contractVersion, 3)
        try BenchmarkConfiguration.dragRace.validate()
    }
    func testInclusiveLimitsAndIndependentSequence() throws {
        for limit in [2,3,4,8,9,10,24,25,26,48,49,50,63,64,65,127,128,129,1024] {
            let config = BenchmarkConfiguration(workload: .upperLimit, upperLimit: limit)
            let signature = try PrimeReference.signature(configuration: config)
            let sequence = PrimeReference.sequence(count: Int.max, limit: limit)
            XCTAssertEqual(signature.count, sequence.count)
            XCTAssertEqual(signature.lastPrime, sequence.last)
            XCTAssertEqual(signature.checksum, sequence.reduce(0,+))
        }
    }
    func testRegistryFilesAndAllVariantExcerpts() throws {
        XCTAssertEqual(SieveImplementation.all.count, 43)
        XCTAssertEqual(Set(SieveImplementation.all.map(\.id)).count, 43)
        for item in SieveImplementation.all where !item.isBaseline {
            XCTAssertTrue(item.supportsThroughput)
            XCTAssertFalse(try PrimeCodeExplorer.sections(for: item).isEmpty)
            for file in item.files() {
                XCTAssertTrue(FileManager.default.fileExists(atPath: item.sourceURL.deletingLastPathComponent().appendingPathComponent(file).path))
            }
        }
    }
    func testThroughputRequiresRealWindowsAndFullSequence() throws {
        let signature = PrimeSignature(count: 2,lastPrime: 3,checksum: 5)
        let good = #"{"elapsed_ns":20000000,"count":2,"last_prime":3,"checksum":5,"passes":20,"primes":[2,3]}"#
        XCTAssertEqual(try BenchmarkRunner.decode(good, expectedSamples: 1, reference: signature, sequence: [2,3], minimumWindowSeconds: 0.02).count, 1)
        for bad in [good.replacingOccurrences(of: "20000000", with: "1000"), good.replacingOccurrences(of: "\"passes\":20", with: "\"passes\":0"), good.replacingOccurrences(of: "[2,3]", with: "[1,4]")] {
            XCTAssertThrowsError(try BenchmarkRunner.decode(bad, expectedSamples: 1, reference: signature, sequence: [2,3], minimumWindowSeconds: 0.02))
        }
        XCTAssertEqual(Statistics.iqr([1,2,3,4]), 1.5)
        XCTAssertEqual(MeasurementWindow(passes: 10,elapsedNS: 5e9,threads: 2).passesPerSecondPerThread, 1)
        XCTAssertThrowsError(try BenchmarkConfiguration(mode: .throughput).validate())
        XCTAssertThrowsError(try BenchmarkConfiguration(rounds: 0).validate())
    }
    func testPythonVariantCalculationThroughputRoundsAndExport() async throws {
        let statuses = await RuntimeDiscovery.discover().filter { $0.id == "python" && $0.available }
        guard !statuses.isEmpty else { throw XCTSkip("Python is unavailable") }
        let unsupported = try await BenchmarkRunner.run(statuses: statuses, configuration: .init(repetitions: 1, mode: .throughput, workload: .upperLimit, upperLimit: 129, durationSeconds: 0.02))
        XCTAssertTrue(unsupported.results.isEmpty)
        XCTAssertNotNil(unsupported.failures["python"])
        for mode in [TimingMode.calculation, .startup, .throughput] {
            let config = BenchmarkConfiguration(repetitions: 2,warmups: 1,mode: mode,workload: .upperLimit,upperLimit: 129,durationSeconds: 0.02,rounds: 2,implementations: .candidates)
            let session = try await BenchmarkRunner.run(statuses: statuses,configuration: config)
            XCTAssertTrue(session.failures.isEmpty, "\(session.failures)")
            let result = try XCTUnwrap(session.results.first)
            XCTAssertEqual(result.samplesNS.count, 4)
            XCTAssertEqual(session.executionOrder?.count, 2)
            XCTAssertEqual(result.roundOrders, [1,2])
            XCTAssertEqual(result.isThroughput, mode == .throughput)
            XCTAssertEqual(result.implementation?.id, "python-bulk")
            XCTAssertEqual(result.launchCommand?.last, mode == .startup ? "0" : "1")
            XCTAssertTrue(SessionStore.csv(session).contains("score_unit"))
            let loaded = try JSONDecoder().decode(BenchmarkSession.self,from: SessionStore.json(session))
            XCTAssertEqual(loaded.results[0].score, result.score)
        }
    }
    func testCancellationPublishesOnlyCompleteRounds() async throws {
        let statuses = await RuntimeDiscovery.discover().filter { $0.id == "python" && $0.available }
        guard !statuses.isEmpty else { throw XCTSkip("Python is unavailable") }
        for interruptedRound in [1, 2] {
            let snapshots = RoundSnapshots()
            let task = Task {
                try await BenchmarkRunner.run(statuses: statuses, configuration: .init(
                    repetitions: 2, warmups: 0, workload: .upperLimit, upperLimit: 129,
                    rounds: 3, implementations: .all)) { event in
                    if case .roundCompleted(let results) = event { await snapshots.append(results) }
                    if case .result(let result) = event, result.roundOrders?.last == interruptedRound {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            }
            do { _ = try await task.value; XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            let completed = await snapshots.values
            XCTAssertEqual(completed.count, interruptedRound - 1)
            if interruptedRound == 2 {
                let results = try XCTUnwrap(completed.last)
                XCTAssertEqual(results.count, 2)
                XCTAssertTrue(results.allSatisfy { $0.roundOrders == [1] && $0.samplesNS.count == 2 })
                var session = BenchmarkSession(configuration: .init(rounds: 3))
                session.results = results
                let restored = try JSONDecoder().decode(BenchmarkSession.self, from: SessionStore.json(session))
                XCTAssertTrue(restored.results.allSatisfy { $0.roundOrders == [1] && $0.samplesNS.count == 2 })
            }
        }
    }
}

private actor RoundSnapshots {
    var values: [[BenchmarkResult]] = []
    func append(_ results: [BenchmarkResult]) { values.append(results) }
}
