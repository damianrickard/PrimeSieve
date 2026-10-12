import XCTest
@testable import PrimeSieveCore

final class RemediationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PrimeSieve-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func language(_ id: String) -> Language { Language.all.first { $0.id == id }! }

    func testMinimalAndShellPathsResolveSamePreferredTools() throws {
        let folder = try temporaryDirectory()
        for name in ["python3", "ruby", "perl"] {
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(name), withDestinationURL: URL(fileURLWithPath: "/bin/echo"))
        }
        let minimal = RuntimeDiscovery.orderedPaths(preferred: [folder.path], inherited: "/usr/bin:/bin:/usr/sbin:/sbin")
        let shell = RuntimeDiscovery.orderedPaths(preferred: [folder.path], inherited: "/usr/bin:\(folder.path):/bin")
        for name in ["python3", "ruby", "perl"] {
            XCTAssertEqual(RuntimeDiscovery.find([name], paths: minimal)?.deletingLastPathComponent().path, folder.path)
            XCTAssertEqual(RuntimeDiscovery.find([name], paths: minimal), RuntimeDiscovery.find([name], paths: shell))
        }
        XCTAssertEqual(RuntimeDiscovery.find(["python3"], overrides: ["python": "/bin/echo"], id: "python", paths: minimal)?.path, "/bin/echo")
        XCTAssertNil(RuntimeDiscovery.find(["python3"], overrides: ["python": "/nonexistent/tool"], id: "python", paths: minimal))
    }

    func testSourceManifestTracksOnlyActualInputs() throws {
        let folder = try temporaryDirectory()
        for name in ["sieve.py", "clock.c", "clock_stubs.c", "sieve_arm64.s", "sieve_x86_64.s"] {
            try Data(name.utf8).write(to: folder.appendingPathComponent(name))
        }
        let python = WorkerSources.names(for: language("python"))
        XCTAssertEqual(python, ["sieve.py"])
        XCTAssertEqual(python, WorkerSources.names(for: language("python"), architecture: "x86_64"))
        let original = try WorkerSources.hash(names: python, directory: folder)
        try Data("changed helper".utf8).write(to: folder.appendingPathComponent("clock.c"))
        XCTAssertEqual(original, try WorkerSources.hash(names: python, directory: folder))
        try Data("changed kernel".utf8).write(to: folder.appendingPathComponent("sieve.py"))
        XCTAssertNotEqual(original, try WorkerSources.hash(names: python, directory: folder))
        XCTAssertEqual(WorkerSources.names(for: language("assembly"), architecture: "arm64"), ["assembly.c", "sieve_arm64.s"])
        XCTAssertEqual(WorkerSources.names(for: language("assembly"), architecture: "x86_64"), ["assembly.c", "sieve_x86_64.s"])
        for id in ["lua", "r", "lisp"] {
            XCTAssertEqual(Set(WorkerSources.names(for: language(id))), Set([language(id).source, "clock.c"]))
        }
        XCTAssertEqual(WorkerSources.names(for: language("ocaml")), ["clock_stubs.c", "sieve.ml"])
        try Data("same contents".utf8).write(to: folder.appendingPathComponent("a"))
        try Data("same contents".utf8).write(to: folder.appendingPathComponent("b"))
        XCTAssertNotEqual(try WorkerSources.hash(names: ["a"], directory: folder), try WorkerSources.hash(names: ["b"], directory: folder))
        XCTAssertEqual(try WorkerSources.hash(names: ["a", "b"], directory: folder), try WorkerSources.hash(names: ["b", "a"], directory: folder))
        XCTAssertThrowsError(try WorkerSources.hash(names: ["missing"], directory: folder))
    }

    func testDotNetSixUsesCompatibleBuildArguments() throws {
        XCTAssertFalse(try DotNetBuild.arguments(major: 6, project: "Worker.csproj").contains("--disable-build-servers"))
        for major in [7, 10] {
            XCTAssertTrue(try DotNetBuild.arguments(major: major, project: "Worker.fsproj").contains("--disable-build-servers"))
        }
        XCTAssertThrowsError(try DotNetBuild.arguments(major: 5, project: "Worker.csproj"))
    }

    func testNodeShebangFindsRenamedOverride() async throws {
        let folder = try temporaryDirectory()
        let node = folder.appendingPathComponent("selected-node")
        try Data("#!/bin/sh\nprintf 'Selected Node\\n'\n".utf8).write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let wrapper = folder.appendingPathComponent("tsc")
        try Data("#!/usr/bin/env node\n".utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        var toolchain = try WorkerToolchain.resolve(language: language("typescript"), primary: wrapper, overrides: ["javascript": node.path])
        try toolchain.bindHelpers(in: folder)
        let output = try await ProcessExecutor.run(executable: wrapper, arguments: ["--version"], environment: toolchain.environment)
        XCTAssertEqual(output.stdout.trimmingCharacters(in: .newlines), "Selected Node")
    }

    func testCustomHelpersAreUsedAndRecorded() async throws {
        let folder = try temporaryDirectory()
        var overrides: [String: String] = [:]
        for (id, names, alias) in [("javascript", ["node"], "custom-node"), ("java", ["javac"], "javac"), ("c", ["clang"], "custom-clang")] {
            let source = try XCTUnwrap(RuntimeDiscovery.find(names))
            let target = folder.appendingPathComponent(alias)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
            overrides[id] = target.path
            if id == "java" {
                try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("java"), withDestinationURL: source.deletingLastPathComponent().appendingPathComponent("java"))
            }
        }
        let ids = ["java", "typescript", "kotlin", "scala", "groovy", "clojure", "lua", "r", "lisp"]
        let statuses = try ids.map { id -> RuntimeStatus in
            let item = language(id)
            return .init(language: item, executable: try XCTUnwrap(RuntimeDiscovery.find(item.executables, overrides: overrides, id: id)), version: "integration test")
        }
        let session = try await BenchmarkRunner.run(statuses: statuses,
            configuration: .init(primeCount: 1000, repetitions: 2, warmups: 1), overrides: overrides)
        XCTAssertTrue(session.failures.isEmpty, "\(session.failures)")
        XCTAssertEqual(session.results.count, ids.count)
        for result in session.results {
            let helper = try XCTUnwrap(result.helperTools?.first)
            let expected = result.id == "typescript" ? "custom-node" : (["lua", "r", "lisp"].contains(result.id) ? "custom-clang" : "java")
            XCTAssertEqual(helper.executablePath, folder.appendingPathComponent(expected).path)
            XCTAssertFalse(helper.version.isEmpty)
            XCTAssertEqual(result.sourceHashFormat, 2)
            XCTAssertNotNil(result.launchCommand)
        }
        let data = try SessionStore.json(session)
        let roundTrip = try JSONDecoder().decode(BenchmarkSession.self, from: data)
        XCTAssertEqual(roundTrip.results.first?.helperTools?.first?.executablePath, session.results.first?.helperTools?.first?.executablePath)
        XCTAssertTrue(SessionStore.csv(session).contains("custom-node"))
        // Remove new optional fields to represent a real historical session.
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var results = try XCTUnwrap(document["results"] as? [[String: Any]])
        for i in results.indices {
            for key in ["helperTools", "launchCommand", "sourceFiles", "sourceHashFormat"] { results[i].removeValue(forKey: key) }
        }
        document["results"] = results
        let old = try JSONDecoder().decode(BenchmarkSession.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertNil(old.results.first?.helperTools)
    }

    func testClojureHasNoBoxingOrReflectionDiagnostics() async throws {
        let item = language("clojure")
        let tool = try XCTUnwrap(RuntimeDiscovery.find(item.executables))
        let toolchain = try WorkerToolchain.resolve(language: item, primary: tool, overrides: [:])
        let output = try await ProcessExecutor.run(executable: tool, arguments: ["-M", item.sourceURL.path, "1000", "9000", "1", "2"], environment: toolchain.environment)
        XCTAssertFalse(output.stderr.lowercased().contains("boxed"), output.stderr)
        XCTAssertFalse(output.stderr.lowercased().contains("reflection"), output.stderr)
        XCTAssertFalse(output.stderr.lowercased().contains("auto-boxing"), output.stderr)
        _ = try BenchmarkRunner.decode(output.stdout, expectedSamples: 2, reference: .init(count: 1000, lastPrime: 7919, checksum: 3682913))
    }
}
