import XCTest
import PrimeSieveCore
@testable import PrimeSieveApp

final class AppModelTests: XCTestCase {
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
