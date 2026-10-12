import Foundation

public struct Language: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let runtime: String
    public let executables: [String]
    public let versionArguments: [String]
    public let source: String
    public let formula: String
    public let family: String
    public let note: String

    public var installCommand: String { "brew install \(formula)" }
    public var sourceURL: URL {
        // SwiftPM's generated accessor only searches the app root; packaged resources live in Contents/Resources.
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("PrimeSieve_PrimeSieveCore.bundle/Workers/\(source)")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return Bundle.module.url(forResource: "Workers", withExtension: nil)!.appendingPathComponent(source)
    }

    public static let all: [Language] = [
        .entry("assembly", "Assembly", "Apple assembler", ["clang"], "assembly.c", "llvm", "Native", "The sieve kernel is handwritten ARM64 or x86-64 assembly; C handles timing and output."),
        .entry("c", "C", "Clang", ["clang"], "sieve.c", "llvm", "Native"),
        .entry("cpp", "C++", "Clang++", ["clang++"], "sieve.cpp", "llvm", "Native"),
        .entry("csharp", "C#", ".NET", ["dotnet"], "sieve.cs", "dotnet", ".NET"),
        .entry("java", "Java", "OpenJDK", ["javac"], "Sieve.java", "openjdk", "JVM"),
        .entry("swift", "Swift", "Swift", ["swiftc"], "sieve.swift", "swift", "Native"),
        .entry("rust", "Rust", "rustc", ["rustc"], "sieve.rs", "rust", "Native"),
        .entry("lisp", "Common Lisp", "SBCL", ["sbcl"], "sieve.lisp", "sbcl", "Lisp"),
        .entry("go", "Go", "Go", ["go"], "sieve.go", "go", "Native"),
        .entry("zig", "Zig", "Zig", ["zig"], "sieve.zig", "zig", "Native", "Uses libc for allocation, timing and output; the sieve is Zig."),
        .entry("d", "D", "LDC", ["ldc2"], "sieve.d", "ldc", "Native"),
        .entry("fortran", "Fortran", "GNU Fortran", ["gfortran", "gfortran-15", "gfortran-14"], "sieve.f90", "gcc", "Native"),
        .entry("nim", "Nim", "Nim", ["nim"], "sieve.nim", "nim", "Native"),
        .entry("fsharp", "F#", ".NET", ["dotnet"], "sieve.fs", "dotnet", ".NET"),
        .entry("kotlin", "Kotlin", "Kotlin/JVM", ["kotlinc"], "sieve.kt", "kotlin", "JVM"),
        .entry("scala", "Scala", "Scala CLI", ["scala"], "sieve.scala", "scala", "JVM", "First compilation may download Scala dependencies."),
        .entry("clojure", "Clojure", "Clojure/JVM", ["clojure"], "sieve.clj", "clojure", "JVM"),
        .entry("haskell", "Haskell", "GHC", ["ghc"], "sieve.hs", "ghc", "Native"),
        .entry("ocaml", "OCaml", "OCaml", ["ocamlopt"], "sieve.ml", "ocaml", "Native"),
        .entry("crystal", "Crystal", "Crystal", ["crystal"], "sieve.cr", "crystal", "Native"),
        .entry("julia", "Julia", "Julia", ["julia"], "sieve.jl", "julia", "Dynamic"),
        .entry("elixir", "Elixir", "Erlang/OTP", ["elixir"], "sieve.exs", "elixir", "BEAM", "Uses an Erlang array; storage differs from mutable byte arrays."),
        .entry("python", "Python", "CPython", ["python3"], "sieve.py", "python", "Interpreted"),
        .entry("ruby", "Ruby", "CRuby", ["ruby"], "sieve.rb", "ruby", "Interpreted"),
        .entry("javascript", "JavaScript", "Node.js", ["node"], "sieve.js", "node", "Dynamic"),
        .entry("typescript", "TypeScript", "TypeScript → Node.js", ["tsc"], "sieve.ts", "typescript", "Dynamic", "Types are erased before execution; uses Node.js like JavaScript."),
        .entry("lua", "Lua", "Lua", ["lua"], "sieve.lua", "lua", "Interpreted", "Uses a Lua table; allocation and storage differ from byte arrays."),
        .entry("perl", "Perl", "Perl", ["perl"], "sieve.pl", "perl", "Interpreted"),
        .entry("php", "PHP", "PHP CLI", ["php"], "sieve.php", "php", "Interpreted"),
        .entry("r", "R", "R", ["Rscript"], "sieve.R", "r", "Interpreted"),
        .entry("pascal", "Pascal", "Free Pascal", ["fpc"], "sieve.pas", "fpc", "Native"),
        .entry("erlang", "Erlang", "Erlang/OTP", ["escript"], "sieve.erl", "erlang", "BEAM", "Uses an Erlang array; storage differs from mutable byte arrays."),
        .entry("racket", "Racket", "Racket", ["racket"], "sieve.rkt", "minimal-racket", "Lisp"),
        .entry("scheme", "Scheme", "Guile", ["guile"], "sieve.scm", "guile", "Lisp"),
        .entry("groovy", "Groovy", "Groovy/JVM", ["groovy"], "sieve.groovy", "groovy", "JVM")
    ]

    private static func entry(_ id: String, _ name: String, _ runtime: String, _ executables: [String],
                              _ source: String, _ formula: String, _ family: String, _ note: String = "") -> Language {
        let version: [String]
        switch id {
        case "java", "kotlin": version = ["-version"]
        case "go", "zig": version = ["version"]
        case "lua": version = ["-v"]
        case "pascal": version = ["-iV"]
        case "erlang": version = ["--version"]
        case "clojure": version = ["-Sdescribe"]
        case "scala": version = ["version"]
        default: version = ["--version"]
        }
        return .init(id: id, name: name, runtime: runtime, executables: executables,
                     versionArguments: version, source: source, formula: formula, family: family, note: note)
    }
}

public enum RuntimeDiscovery {
    public static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = ["/opt/homebrew/bin", "/opt/homebrew/opt/ruby/bin", "/usr/local/bin", "/usr/local/opt/ruby/bin", "\(home)/.cargo/bin",
                  "/usr/local/share/dotnet", "/opt/homebrew/opt/openjdk/bin", "/usr/local/opt/openjdk/bin",
                  "/opt/homebrew/opt/ruby/bin", "/opt/homebrew/opt/llvm/bin"]
        // Support versioned JDK installations and Julia's normal macOS application install.
        for base in ["/Library/Java/JavaVirtualMachines", "\(home)/Library/Java/JavaVirtualMachines"] {
            if let folders = try? FileManager.default.contentsOfDirectory(atPath: base) {
                paths += folders.map { "\(base)/\($0)/Contents/Home/bin" }
            }
        }
        if let applications = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            paths += applications.filter { $0.hasPrefix("Julia-") }.map { "/Applications/\($0)/Contents/Resources/julia/bin" }
        }
        return orderedPaths(preferred: paths, inherited: ProcessInfo.processInfo.environment["PATH"] ?? "")
    }

    /// Prefer known toolchain locations consistently, even under Finder's minimal PATH.
    static func orderedPaths(preferred: [String], inherited: String) -> [String] {
        let system = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let paths = preferred + inherited.split(separator: ":").map(String.init).filter { !system.contains($0) } + system
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func find(_ names: [String], overrides: [String: String] = [:], id: String? = nil,
                            paths: [String]? = nil) -> URL? {
        if let id, let override = overrides[id] {
            // An invalid explicit selection must not silently fall back to another runtime.
            return FileManager.default.isExecutableFile(atPath: override) ? URL(fileURLWithPath: override) : nil
        }
        // Skip Apple's Java launcher placeholders: they can open an installation dialog.
        for name in names {
            for path in paths ?? searchPaths {
                let full = URL(fileURLWithPath: path).appendingPathComponent(name)
                if ["java", "javac"].contains(name) && full.path == "/usr/bin/\(name)" { continue }
                if FileManager.default.isExecutableFile(atPath: full.path) { return full }
            }
        }
        return nil
    }

    public static func discover(overrides: [String: String] = [:]) async -> [RuntimeStatus] {
        var statuses: [RuntimeStatus] = []
        for language in Language.all {
            if Task.isCancelled { break }
            guard let executable = find(language.executables, overrides: overrides, id: language.id) else {
                statuses.append(.init(language: language, executable: nil, version: "Not installed")); continue
            }
            do {
                var toolchain = try WorkerToolchain.resolve(language: language, primary: executable, overrides: overrides)
                let probeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("PrimeSieve-discovery-\(UUID())")
                defer { try? FileManager.default.removeItem(at: probeDirectory) }
                try toolchain.bindHelpers(in: probeDirectory)
                var args = language.versionArguments
                // escript does not support a version flag; ask erl directly instead.
                var probe = executable
                if language.id == "erlang" {
                    probe = executable.deletingLastPathComponent().appendingPathComponent("erl")
                    args = ["-noshell", "-eval", "io:format(\"OTP ~s~n\", [erlang:system_info(otp_release)]), halt()."]
                }
                let output = try await ProcessExecutor.run(executable: probe, arguments: args, timeout: 15, environment: toolchain.environment)
                let text = output.stdout + "\n" + output.stderr
                let version = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? language.runtime
                statuses.append(.init(language: language, executable: executable, version: version))
            } catch {
                if Task.isCancelled { break }
                statuses.append(.init(language: language, executable: nil, version: "Runtime check failed: \(error.localizedDescription)"))
            }
        }
        return statuses
    }
}
