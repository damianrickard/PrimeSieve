import XCTest
import PrimeSieveCore
@testable import PrimeSieveApp

final class AppModelTests: XCTestCase {
    @MainActor
    func testInvalidHiddenWorkloadInputDoesNotBlockVisibleInput() throws {
        let model = AppModel()
        model.mode = .calculation
        model.workload = .firstN
        model.primeCount = "100"
        for hidden in ["", "typo", "0", "300000000"] {
            model.upperLimit = hidden
            let config = try XCTUnwrap(model.configuration)
            try config.validate()
            XCTAssertEqual(config.primeCount, 100)
            XCTAssertEqual(config.upperLimit, 1_000_000)
        }
        model.workload = .upperLimit
        model.upperLimit = "1,024"
        for hidden in ["", "typo", "0", "300000000"] {
            model.primeCount = hidden
            let config = try XCTUnwrap(model.configuration)
            try config.validate()
            XCTAssertEqual(config.upperLimit, 1024)
            XCTAssertEqual(config.primeCount, 100_000)
        }
        model.primeCount = "42"
        XCTAssertEqual(model.configuration?.primeCount, 42)
        model.workload = .firstN
        XCTAssertEqual(model.configuration?.upperLimit, 1024)
    }

    @MainActor
    func testInvalidVisibleInputNamesTheActiveField() {
        let model = AppModel()
        model.mode = .calculation
        model.workload = .firstN
        model.primeCount = ""
        model.run()
        XCTAssertEqual(model.errorMessage, "Enter a whole number for the prime count.")
        model.workload = .upperLimit
        model.upperLimit = "typo"
        model.run()
        XCTAssertEqual(model.errorMessage, "Enter a whole number for the inclusive upper limit.")
        XCTAssertFalse(model.isRunning)
    }

    @MainActor
    func testClearHistoryPreservesVisibleResultAndBlocksDuringRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BenchmarkSession(configuration: .init())
        try SessionStore.save(session, directory: directory)
        let model = AppModel(historyDirectory: directory)
        model.selectHistory(session)
        model.isRunning = true
        XCTAssertNotNil(model.clearHistory())
        XCTAssertEqual(SessionStore.load(directory: directory).count, 1)
        model.isRunning = false
        XCTAssertNil(model.clearHistory())
        XCTAssertTrue(model.history.isEmpty)
        XCTAssertTrue(SessionStore.load(directory: directory).isEmpty)
        XCTAssertEqual(model.session?.id, session.id)
        XCTAssertEqual(model.primeCount, String(session.configuration.primeCount))
    }

    @MainActor
    func testClearHistoryReportsFailure() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("not a directory".utf8).write(to: path)
        let model = AppModel(historyDirectory: path)
        XCTAssertTrue(model.clearHistory()?.contains("could not be fully cleared") ?? false)
    }

    @MainActor
    func testRuntimeChangeDuringDiscoveryQueuesLatestSelection() async throws {
        let gate = DiscoveryGate()
        let model = AppModel(discover: { paths in await gate.discover(paths) })
        model.overrides = ["python": "/first/python3"]
        let initial = Task { await model.refresh() }
        await gate.waitUntilStarted()
        XCTAssertTrue(model.isDiscovering)
        model.overrides = ["python": "/second/python3"]
        await model.refresh()
        model.overrides = ["python": "/latest/python3"]
        await model.refresh()
        XCTAssertTrue(model.isDiscovering)
        await gate.release()
        await initial.value
        XCTAssertFalse(model.isDiscovering)
        XCTAssertEqual(model.runtimes.first?.executable?.path, "/latest/python3")
        let requests = await gate.requests
        XCTAssertEqual(requests.map { $0["python"] }, ["/first/python3", "/latest/python3"])
    }
}

private actor DiscoveryGate {
    var requests: [[String: String]] = []
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { pending?.resume(); pending = nil }
    func discover(_ paths: [String: String]) async -> [RuntimeStatus] {
        requests.append(paths)
        if requests.count == 1 {
            await withCheckedContinuation { continuation in
                pending = continuation
                started?.resume(); started = nil
            }
        }
        let language = Language.all.first { $0.id == "python" }!
        return [.init(language: language, executable: URL(fileURLWithPath: paths["python"]!), version: "test")]
    }
}
