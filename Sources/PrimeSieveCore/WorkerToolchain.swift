import Foundation

/// Resolve shared tools once so preparation, wrapper scripts and execution agree.
struct WorkerToolchain {
    struct Helper {
        var role: String
        var executable: URL
        var versionArguments: [String]
    }
    var helpers: [Helper] = []
    var environment: [String: String] = [:]

    /// A selected Node may have any filename. Give env-based compiler wrappers a canonical alias.
    mutating func bindHelpers(in directory: URL) throws {
        guard let node = helpers.first(where: { $0.role == "node" }) else { return }
        let aliases = directory.appendingPathComponent("toolchain-bin")
        try FileManager.default.createDirectory(at: aliases, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliases.appendingPathComponent("node"), withDestinationURL: node.executable)
        environment["PATH"] = aliases.path + ":" + (environment["PATH"] ?? "")
    }

    func executable(for role: String) throws -> URL {
        guard let helper = helpers.first(where: { $0.role == role }) else {
            throw BenchmarkError.message("Missing helper tool: \(role).")
        }
        return helper.executable
    }

    static func resolve(language: Language, primary: URL, overrides: [String: String]) throws -> Self {
        var result = Self()
        func require(_ names: [String], id: String) throws -> URL {
            guard let tool = RuntimeDiscovery.find(names, overrides: overrides, id: id) else {
                throw BenchmarkError.message("Select or install a working \(names.joined(separator: " or ")) for \(language.name).")
            }
            return tool
        }
        if language.family == "JVM" {
            let compiler = language.id == "java" ? primary : try require(["javac"], id: "java")
            let java = compiler.deletingLastPathComponent().appendingPathComponent("java")
            guard FileManager.default.isExecutableFile(atPath: java.path) else {
                throw BenchmarkError.message("The selected Java compiler needs a java executable in the same directory.")
            }
            result.helpers.append(.init(role: "java", executable: java, versionArguments: ["-version"]))
            result.environment["JAVA_HOME"] = java.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().path
            result.environment["JAVA_CMD"] = java.path
            result.environment["JAVACMD"] = java.path
        }
        if language.id == "typescript" {
            result.helpers.append(.init(role: "node", executable: try require(["node"], id: "javascript"), versionArguments: ["--version"]))
        }
        if ["lua", "r", "lisp"].contains(language.id) {
            result.helpers.append(.init(role: "clock compiler", executable: try require(["clang"], id: "c"), versionArguments: ["--version"]))
        }
        let directories = result.helpers.map { $0.executable.deletingLastPathComponent().path } + [primary.deletingLastPathComponent().path]
        result.environment["PATH"] = (directories + RuntimeDiscovery.searchPaths).joined(separator: ":")
        return result
    }

    func records() async throws -> [ToolRecord] {
        var records: [ToolRecord] = []
        for helper in helpers {
            let output = try await ProcessExecutor.run(executable: helper.executable,
                arguments: helper.versionArguments, timeout: 15, environment: environment)
            let version = (output.stdout + "\n" + output.stderr).split(separator: "\n").first.map(String.init) ?? "Unknown version"
            records.append(.init(role: helper.role, executablePath: helper.executable.path, version: version))
        }
        return records
    }
}
