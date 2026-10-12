import XCTest
@testable import PrimeSieveCore

final class SessionStoreTests: XCTestCase {
    func testClearRemovesSavedAndCorruptSessionsButPreservesOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = root.appendingPathComponent("history")
        let session = BenchmarkSession(configuration: .init())
        try SessionStore.save(session, directory: history)
        XCTAssertEqual(SessionStore.load(directory: history).map(\.id), [session.id])
        try Data("broken JSON".utf8).write(to: history.appendingPathComponent("corrupt.json"))
        let notes = history.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: notes)
        let nested = history.appendingPathComponent("folder.json")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("keep nested".utf8).write(to: nested.appendingPathComponent("saved.json"))
        let exported = root.appendingPathComponent("export.json")
        try SessionStore.json(session).write(to: exported)
        let link = history.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: exported)

        try SessionStore.clear(directory: history)

        XCTAssertTrue(SessionStore.load(directory: history).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.appendingPathComponent("\(session.id).json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.appendingPathComponent("corrupt.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try String(contentsOf: notes), "keep")
        XCTAssertEqual(try String(contentsOf: nested.appendingPathComponent("saved.json")), "keep nested")
        XCTAssertEqual(try Data(contentsOf: exported), try SessionStore.json(session))
        // Clearing an already empty store is safe, and future runs can still save history.
        try SessionStore.clear(directory: history)
        try SessionStore.save(session, directory: history)
        XCTAssertEqual(SessionStore.load(directory: history).map(\.id), [session.id])
    }

    func testClearMissingDirectoryAndReportInvalidLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNoThrow(try SessionStore.clear(directory: root))
        try Data("not a directory".utf8).write(to: root)
        XCTAssertThrowsError(try SessionStore.clear(directory: root))
        XCTAssertEqual(try String(contentsOf: root), "not a directory")
    }
}
