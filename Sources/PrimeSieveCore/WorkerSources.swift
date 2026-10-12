import Foundation
import CryptoKit

/// The manifest includes only inputs used by this worker, including generated .NET build settings.
enum WorkerSources {
    static func names(for language: Language, architecture: String = BenchmarkSession.architecture) -> [String] {
        var names = [language.source]
        switch language.id {
        case "assembly": names.append("sieve_\(architecture).s")
        case "lua", "r", "lisp": names.append("clock.c")
        case "ocaml": names.append("clock_stubs.c")
        default: break
        }
        return names.sorted()
    }

    static func hash(names: [String], directory: URL) throws -> String {
        var hasher = SHA256()
        hasher.update(data: Data("PrimeSieve source manifest v2\n".utf8))
        // Length-prefixed file names and contents prevent ambiguous concatenations.
        for name in names.sorted() {
            for data in [Data(name.utf8), try Data(contentsOf: directory.appendingPathComponent(name))] {
                hasher.update(data: Data("\(data.count):".utf8))
                hasher.update(data: data)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum DotNetBuild {
    static func arguments(major: Int, project: String) throws -> [String] {
        guard major >= 6 else { throw BenchmarkError.message("A .NET SDK version 6 or newer is required.") }
        var arguments = ["build", project, "-c", "Release", "-o", "out", "--nologo"]
        if major >= 7 { arguments.append("--disable-build-servers") }
        return arguments
    }
}
