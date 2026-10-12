import Foundation
import Darwin

public struct CommandOutput: Sendable {
    public let stdout: String
    public let stderr: String
    public let elapsedNS: Double
}

public enum ProcessExecutor {
    public static func run(executable: URL, arguments: [String], directory: URL? = nil,
                           timeout: Double = 120, environment overrides: [String: String] = [:]) async throws -> CommandOutput {
        try Task.checkCancellation()
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("PrimeSieve-process-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let outURL = folder.appendingPathComponent("stdout"), errURL = folder.appendingPathComponent("stderr")
        files.createFile(atPath: outURL.path, contents: nil)
        files.createFile(atPath: errURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: outURL), err = try FileHandle(forWritingTo: errURL)
        defer { try? out.close(); try? err.close() }
        let process = Process()
        // Request this app's architecture explicitly so a Rosetta-only custom runtime cannot silently skew results.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        process.arguments = ["-\(BenchmarkSession.architecture)", executable.path] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = out; process.standardError = err
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = RuntimeDiscovery.searchPaths.joined(separator: ":")
        environment["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
        environment["DOTNET_NOLOGO"] = "1"
        environment["MSBUILDDISABLENODEREUSE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment.merge(overrides) { _, selected in selected }
        process.environment = environment
        let completion = ProcessCompletion()
        process.terminationHandler = { _ in completion.finish() }
        let start = DispatchTime.now().uptimeNanoseconds
        try process.run()
        let childGroup = getpgid(process.processIdentifier)
        let ownsGroup = childGroup == process.processIdentifier && childGroup != getpgrp()
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 > timeout {
                    throw BenchmarkError.message("Timed out after \(Int(timeout)) seconds.")
                }
                let outputSize = ((try? files.attributesOfItem(atPath: outURL.path)[.size] as? UInt64) ?? 0)
                    + ((try? files.attributesOfItem(atPath: errURL.path)[.size] as? UInt64) ?? 0)
                if outputSize > 8_000_000 {
                    throw BenchmarkError.message("Worker output exceeded the 8 MB limit.")
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        } catch {
            if process.isRunning {
                if ownsGroup { Darwin.kill(-childGroup, SIGTERM) }
                else { process.terminate() }
                // Ensure an unresponsive worker does not survive cancellation or a timeout.
                for _ in 0..<20 where process.isRunning { usleep(10_000) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                if ownsGroup { Darwin.kill(-childGroup, SIGKILL) }
                process.waitUntilExit()
            }
            throw error
        }
        process.waitUntilExit()
        let elapsed = Double((completion.end ?? DispatchTime.now().uptimeNanoseconds) - start)
        let stdout = String(decoding: try Data(contentsOf: outURL), as: UTF8.self)
        let stderr = String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw BenchmarkError.message(String((stderr.isEmpty ? stdout : stderr).suffix(4000)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Process exited with status \(process.terminationStatus)." : String((stderr.isEmpty ? stdout : stderr).suffix(4000)))
        }
        return .init(stdout: stdout, stderr: stderr, elapsedNS: elapsed)
    }
}

private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64?
    var end: UInt64? { lock.lock(); defer { lock.unlock() }; return value }
    func finish() { lock.lock(); value = DispatchTime.now().uptimeNanoseconds; lock.unlock() }
}
