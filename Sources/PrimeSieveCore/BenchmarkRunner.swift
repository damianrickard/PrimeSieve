import Foundation

public enum BenchmarkEvent: Sendable {
    case preparingReference
    case preparing(String, Int, Int)
    case measuring(String, Int, Int)
    case roundOrder([String])
    case result(BenchmarkResult)
    case roundCompleted([BenchmarkResult])
    case failure(String, String)
}

public enum BenchmarkRunner {
    private struct Worker {
        var directory: URL
        var prepared: Prepared
        var environment: [String: String]
        var result: BenchmarkResult
    }
    public static func run(statuses: [RuntimeStatus], configuration: BenchmarkConfiguration,
                           overrides: [String: String] = [:],
                           event: @escaping @Sendable (BenchmarkEvent) async -> Void = { _ in }) async throws -> BenchmarkSession {
        var configuration = configuration
        configuration.contractVersion = 3
        try configuration.validate()
        try SieveImplementation.validateRegistry()
        guard !statuses.isEmpty, statuses.allSatisfy(\.available) else {
            throw BenchmarkError.message("Select at least one available language.")
        }
        let choices = statuses.flatMap { status in
            SieveImplementation.selected(for: status.id, configuration: configuration).map { (status, $0) }
        }
        guard !choices.isEmpty else { throw BenchmarkError.message("No implementations match the selected languages and filter.") }
        if let ids = configuration.implementationIDs {
            let available = Set(choices.map { $0.1.id })
            guard !ids.isEmpty, Set(ids).isSubset(of: available) else { throw BenchmarkError.message("Unknown implementation or missing selected runtime.") }
        }
        var session = BenchmarkSession(configuration: configuration)
        await event(.preparingReference)
        let reference = try PrimeReference.signature(configuration: configuration)
        let sequence = configuration.sieveLimit <= 100_000 ? PrimeReference.sequence(count: reference.count, limit: configuration.sieveLimit) : nil
        var workers: [Worker] = []
        defer { for worker in workers { try? FileManager.default.removeItem(at: worker.directory) } }
        for (index, choice) in choices.enumerated() {
            let (status, implementation) = choice
            try Task.checkCancellation()
            await event(.preparing("\(status.language.name) · \(implementation.name)", index, choices.count))
            do {
                if configuration.mode == .throughput && !implementation.supportsThroughput {
                    throw BenchmarkError.message("This baseline has no duration harness. Choose a tuned variant for sieve throughput.")
                }
                workers.append(try await prepareWorker(status: status, implementation: implementation, config: configuration, reference: reference, overrides: overrides))
            } catch is CancellationError { throw CancellationError() }
            catch {
                session.failures[implementation.id] = error.localizedDescription
                await event(.failure(implementation.id, error.localizedDescription))
            }
        }
        for round in 0..<configuration.rounds {
            let order = workers.indices.filter { session.failures[workers[$0].result.id] == nil }.shuffled()
            session.executionOrder?.append(order.map { workers[$0].result.id })
            await event(.roundOrder(order.map { workers[$0].result.id }))
            for (position, index) in order.enumerated() {
                try Task.checkCancellation()
                let worker = workers[index]
                let implementation = worker.result.implementation!
                await event(.measuring("\(worker.result.displayName) · round \(round + 1)/\(configuration.rounds)", round * choices.count + position, configuration.rounds * choices.count))
                do {
                    let base = [String(reference.count), String(configuration.sieveLimit)]
                    func arguments(warm: Int, runs: Int, fullSequence: Bool = false) -> [String] {
                        var args = worker.prepared.arguments + base + [String(warm), String(runs)]
                        if !implementation.isBaseline {
                            args += [configuration.mode == .throughput ? "throughput" : "calculation",
                                     String(configuration.durationSeconds), configuration.workload == .firstN ? "count" : "limit",
                                     implementation.variant, sequence != nil && (configuration.mode != .startup || fullSequence) ? "1" : "0"]
                        }
                        return args
                    }
                    workers[index].result.launchCommand = [worker.prepared.executable.path] + arguments(warm: configuration.mode == .startup ? 0 : configuration.warmups, runs: configuration.mode == .startup ? 1 : configuration.repetitions)
                    var samples: [WorkerSample] = []
                    var elapsed: [Double] = []
                    if configuration.mode == .startup {
                        for _ in 0..<configuration.repetitions {
                            let output = try await ProcessExecutor.run(executable: worker.prepared.executable, arguments: arguments(warm: 0, runs: 1),
                                directory: worker.directory, timeout: configuration.timeoutSeconds, environment: worker.environment)
                            samples += try decode(output.stdout, expectedSamples: 1, reference: reference)
                            elapsed.append(output.elapsedNS)
                        }
                        // Full output is checked separately, after startup samples, so it cannot inflate their wall time.
                        if round == 0, !implementation.isBaseline, let sequence {
                            let verification = try await ProcessExecutor.run(executable: worker.prepared.executable,
                                arguments: arguments(warm: 0, runs: 1, fullSequence: true), directory: worker.directory,
                                timeout: configuration.timeoutSeconds, environment: worker.environment)
                            _ = try decode(verification.stdout, expectedSamples: 1, reference: reference, sequence: sequence)
                        }
                    } else {
                        let output = try await ProcessExecutor.run(executable: worker.prepared.executable,
                            arguments: arguments(warm: configuration.warmups, runs: configuration.repetitions), directory: worker.directory,
                            timeout: configuration.timeoutSeconds, environment: worker.environment)
                        samples = try decode(output.stdout, expectedSamples: configuration.repetitions, reference: reference,
                                             sequence: implementation.isBaseline ? nil : sequence,
                                             minimumWindowSeconds: configuration.mode == .throughput ? configuration.durationSeconds : nil)
                        elapsed = samples.map(\.elapsedNS)
                    }
                    workers[index].result.samplesNS += elapsed
                    workers[index].result.roundOrders?.append(round + 1)
                    if configuration.mode == .throughput {
                        workers[index].result.windows = (workers[index].result.windows ?? []) + samples.map { .init(passes: $0.passes!, elapsedNS: $0.elapsedNS) }
                    }
                    // Per-worker events report progress; only complete rounds enter the leaderboard.
                    await event(.result(workers[index].result))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    // Never rank an entry which failed any round as a completed comparison.
                    session.results.removeAll { $0.id == implementation.id }
                    session.failures[implementation.id] = error.localizedDescription
                    await event(.failure(implementation.id, error.localizedDescription))
                }
            }
            try Task.checkCancellation()
            session.results = workers.map(\.result).filter { session.failures[$0.id] == nil }
            await event(.roundCompleted(session.results))
        }
        session.results.sort(by: BenchmarkResult.faster)
        session.completed = true
        return session
    }
    private static func prepareWorker(status: RuntimeStatus, implementation: SieveImplementation,
                                      config: BenchmarkConfiguration, reference: PrimeSignature,
                                      overrides: [String: String]) async throws -> Worker {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PrimeSieve-\(implementation.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var names = implementation.files()
            for name in names {
                try FileManager.default.copyItem(at: status.language.sourceURL.deletingLastPathComponent().appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            var toolchain = try WorkerToolchain.resolve(language: status.language, primary: status.executable!, overrides: overrides)
            try toolchain.bindHelpers(in: directory)
            let helpers = try await toolchain.records()
            let start = DispatchTime.now().uptimeNanoseconds
            let prepared = try await prepare(language: status.language, tool: status.executable!, directory: directory,
                                             timeout: max(config.timeoutSeconds, 120), toolchain: toolchain, implementation: implementation)
            let compilation = prepared.compiled ? Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 : 0
            names += prepared.generatedSources
            var result = BenchmarkResult(id: implementation.id, language: status.language.name, runtimeVersion: status.version,
                executablePath: status.executable!.path, samplesNS: [], compilationSeconds: compilation, signature: reference,
                command: prepared.buildDescription, sourceHash: try WorkerSources.hash(names: names, directory: directory),
                helperTools: helpers, launchCommand: [prepared.executable.path] + prepared.arguments, sourceFiles: names.sorted(), sourceHashFormat: 2)
            result.implementation = implementation; result.roundOrders = []; result.contract = config.measurementContract
            return Worker(directory: directory, prepared: prepared, environment: toolchain.environment, result: result)
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
    public static func decode(_ output: String, expectedSamples: Int, reference: PrimeSignature,
                              sequence: [Int]? = nil, minimumWindowSeconds: Double? = nil) throws -> [WorkerSample] {
        var samples: [WorkerSample] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{") else { continue }
            let sample: WorkerSample
            do { sample = try JSONDecoder().decode(WorkerSample.self, from: Data(trimmed.utf8)) }
            catch { throw BenchmarkError.message("Worker returned malformed timing data: \(trimmed.prefix(180))") }
            guard sample.elapsedNS.isFinite, sample.elapsedNS >= 0, sample.signature == reference else {
                throw BenchmarkError.message("Correctness verification failed. This result was excluded from the leaderboard.")
            }
            if let sequence, sample.primes != sequence { throw BenchmarkError.message("Complete prime sequence verification failed.") }
            if let seconds = minimumWindowSeconds {
                guard let passes = sample.passes, passes > 0, sample.elapsedNS >= seconds * 1e9 else {
                    throw BenchmarkError.message("Invalid throughput window: positive passes and the full requested duration are required.")
                }
            }
            samples.append(sample)
        }
        guard samples.count == expectedSamples else { throw BenchmarkError.message("Expected \(expectedSamples) measurements; received \(samples.count).") }
        return samples
    }

    private struct Prepared {
        var executable: URL
        var arguments: [String] = []
        var compiled = false
        var buildDescription: [String] = []
        var generatedSources: [String] = []
    }

    private static func prepare(language: Language, tool: URL, directory: URL, timeout: Double, toolchain: WorkerToolchain, implementation: SieveImplementation) async throws -> Prepared {
        let binary = directory.appendingPathComponent("worker")
        let source = implementation.source
        func compile(_ args: [String], executable: URL? = nil) async throws {
            _ = try await ProcessExecutor.run(executable: executable ?? tool, arguments: args, directory: directory, timeout: timeout, environment: toolchain.environment)
        }
        func native(_ args: [String]) async throws -> Prepared {
            try await compile(args)
            return .init(executable: binary, compiled: true, buildDescription: [tool.path] + args)
        }
        switch language.id {
        case "c": return try await native(["-O3", "-std=c11", source, "-o", binary.path])
        case "cpp": return try await native(["-O3", "-std=c++17", source, "-o", binary.path])
        case "assembly": return try await native(["-O3", source, implementation.isBaseline ? "sieve_\(BenchmarkSession.architecture).s" : "tuned_\(BenchmarkSession.architecture).s", "-o", binary.path])
        case "swift": return try await native(["-O", source, "-o", binary.path])
        case "rust": return try await native(["-C", "opt-level=3", source, "-o", binary.path])
        case "go": return try await native(["build", "-o", binary.path, source])
        case "zig": return try await native(["build-exe", source, "-O", "ReleaseFast", "-lc", "-femit-bin=\(binary.path)"])
        case "d": return try await native(["-O3", "-release", source, "-of=\(binary.path)"])
        case "fortran": return try await native(["-O3", source, "-o", binary.path])
        case "nim": return try await native(["c", "-d:release", "--out:\(binary.path)", source])
        case "haskell": return try await native(["-O2", source, "-o", binary.path])
        case "ocaml": return try await native(["-O3", "clock_stubs.c", source, "-o", binary.path])
        case "crystal": return try await native(["build", "--release", source, "-o", binary.path])
        case "pascal": return try await native(["-O3", "-o\(binary.path)", source])
        case "csharp", "fsharp":
            let version = try await ProcessExecutor.run(executable: tool, arguments: ["--version"], timeout: 15)
            guard let major = Int(version.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").first ?? ""), major >= 6 else {
                throw BenchmarkError.message("A .NET SDK version 6 or newer is required.")
            }
            let extensionName = language.id == "csharp" ? "csproj" : "fsproj"
            let project = """
            <Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net\(major).0</TargetFramework><EnableDefaultCompileItems>false</EnableDefaultCompileItems><InvariantGlobalization>true</InvariantGlobalization></PropertyGroup><ItemGroup><Compile Include="\(source)" /></ItemGroup></Project>
            """
            try project.write(to: directory.appendingPathComponent("Worker.\(extensionName)"), atomically: true, encoding: .utf8)
            let args = try DotNetBuild.arguments(major: major, project: "Worker.\(extensionName)")
            try await compile(args)
            return .init(executable: tool, arguments: [directory.appendingPathComponent("out/Worker.dll").path], compiled: true, buildDescription: [tool.path] + args, generatedSources: ["Worker.\(extensionName)"])
        case "java":
            let args = [source, "-d", directory.path]; try await compile(args)
            let java = try toolchain.executable(for: "java")
            return .init(executable: java, arguments: ["-cp", directory.path, "Sieve"], compiled: true, buildDescription: [tool.path] + args)
        case "kotlin":
            let args = [source, "-include-runtime", "-d", "worker.jar"]; try await compile(args)
            return .init(executable: try toolchain.executable(for: "java"), arguments: ["-jar", "worker.jar"], compiled: true, buildDescription: [tool.path] + args)
        case "scala":
            let args = ["--power", "package", source, "--assembly", "--server=false", "--java-home", toolchain.environment["JAVA_HOME"]!, "-o", "worker.jar"]
            try await compile(args)
            return .init(executable: try toolchain.executable(for: "java"), arguments: ["-jar", "worker.jar"], compiled: true, buildDescription: [tool.path] + args)
        case "groovy":
            // Compile before launching the JVM, keeping compilation outside startup timing.
            let groovyc = tool.deletingLastPathComponent().appendingPathComponent("groovyc")
            let args = ["-d", directory.path, source]
            try await compile(args, executable: groovyc)
            let resolved = tool.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
            let libraryDirectory = [resolved.appendingPathComponent("lib"), resolved.appendingPathComponent("libexec/lib")].first { candidate in
                let files = (try? FileManager.default.contentsOfDirectory(atPath: candidate.path)) ?? []
                return files.contains { $0.hasPrefix("groovy-") && $0.hasSuffix(".jar") }
            }
            guard let libraryDirectory else { throw BenchmarkError.message("Could not locate the Groovy runtime JARs next to the selected compiler.") }
            let libraries = libraryDirectory.appendingPathComponent("*").path
            return .init(executable: try toolchain.executable(for: "java"), arguments: ["-cp", "\(directory.path):\(libraries)", "Sieve"], compiled: true, buildDescription: [groovyc.path] + args)
        case "typescript":
            let args = [source, "--target", "ES2020", "--module", "commonjs", "--outDir", "out"]
            // Both native tsc and JavaScript-based tsc are supported; wrappers inherit the Node alias.
            let node = try toolchain.executable(for: "node")
            try await compile(args)
            return .init(executable: node, arguments: ["out/sieve.js"], compiled: true, buildDescription: [tool.path] + args)
        case "lua", "r", "lisp":
            let clang = try toolchain.executable(for: "clock compiler")
            var args = ["-O2", "-dynamiclib", "clock.c", "-o", "clock.dylib"]
            if language.id == "lua" { args += ["-DLUA_CLOCK", "-undefined", "dynamic_lookup"] }
            try await compile(args, executable: clang)
            let launch = language.id == "lisp" ? ["--script", source] : [source]
            return .init(executable: tool, arguments: launch, compiled: true, buildDescription: [clang.path] + args)
        case "clojure": return .init(executable: tool, arguments: ["-M", source], buildDescription: [tool.path, "-M", source])
        case "python": return .init(executable: tool, arguments: ["-B", source], buildDescription: [tool.path, "-B", source])
        case "scheme":
            // Use the selected Guile for both compilation and execution; neither mode times compilation.
            let args = ["--no-auto-compile", "-c", "(compile-file \"sieve.scm\" #:output-file \"worker.go\")"]
            try await compile(args)
            return .init(executable: tool, arguments: ["--no-auto-compile", "-c", "(load-compiled \"worker.go\")"],
                         compiled: true, buildDescription: [tool.path] + args)
        case "julia": return .init(executable: tool, arguments: ["--startup-file=no", "--threads=1", source], buildDescription: [tool.path, "--startup-file=no", "--threads=1", source])
        default: return .init(executable: tool, arguments: [source], buildDescription: [tool.path, source])
        }
    }
}
