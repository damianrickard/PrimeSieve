import Foundation
import PrimeSieveCore

@main
struct CLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.first == "verify" {
                let statuses = await RuntimeDiscovery.discover().filter(\.available)
                for count in [1, 2, 5, 1000] {
                    let config = BenchmarkConfiguration(primeCount: count, repetitions: 2, warmups: 1)
                    let session = try await BenchmarkRunner.run(statuses: statuses, configuration: config)
                    guard session.failures.isEmpty else {
                        throw BenchmarkError.message("Verification failed for \(count) primes: \(session.failures)")
                    }
                    print("PASS: \(statuses.count) languages, first \(count) primes, 2 verified measurements each")
                }
                return
            }
            if args.first == "list" || args.isEmpty {
                for status in await RuntimeDiscovery.discover() {
                    print("\(status.available ? "READY" : "MISSING")\t\(status.id)\t\(status.language.name)\t\(status.version)")
                }
                return
            }
            guard args.first == "run" else { throw BenchmarkError.message("Usage: primesieve-cli list | verify | run --languages c,swift,pascal --count 100000 [--repetitions 7 --warmups 3 --mode calculation|startup --timeout 120 --output results.json]") }
            func option(_ name: String, default value: String) -> String {
                guard let index = args.firstIndex(of: name), index+1 < args.count else { return value }
                return args[index+1]
            }
            let ids = Set(option("--languages", default: "c,cpp,swift,assembly,python,javascript").split(separator: ",").map(String.init))
            let unknown = ids.subtracting(Set(Language.all.map(\.id)))
            guard unknown.isEmpty else { throw BenchmarkError.message("Unknown languages: \(unknown.sorted().joined(separator: ", "))") }
            guard let count = Int(option("--count", default: "100000")),
                  let repetitions = Int(option("--repetitions", default: "7")),
                  let warmups = Int(option("--warmups", default: "3")),
                  let timeout = Double(option("--timeout", default: "120")) else {
                throw BenchmarkError.message("Numeric options must contain valid numbers.")
            }
            let modeString = option("--mode", default: "calculation")
            guard ["calculation", "startup"].contains(modeString) else { throw BenchmarkError.message("Mode must be calculation or startup.") }
            let config = BenchmarkConfiguration(primeCount: count, repetitions: repetitions, warmups: warmups,
                timeoutSeconds: timeout, mode: modeString == "startup" ? .startup : .calculation)
            try config.validate()
            let statuses = await RuntimeDiscovery.discover().filter { ids.contains($0.id) }
            let unavailable = statuses.filter { !$0.available }
            guard unavailable.isEmpty else { throw BenchmarkError.message("Install missing runtimes: \(unavailable.map { $0.language.name }.joined(separator: ", "))") }
            let session = try await BenchmarkRunner.run(statuses: statuses, configuration: config) { event in
                switch event {
                case .preparing(let language, _, _): FileHandle.standardError.write(Data("Preparing \(language)…\n".utf8))
                case .failure(let language, let error): FileHandle.standardError.write(Data("\(language): \(error)\n".utf8))
                default: break
                }
            }
            print(SessionStore.csv(session), terminator: "")
            let path = option("--output", default: "")
            if !path.isEmpty { try SessionStore.json(session).write(to: URL(fileURLWithPath: path), options: .atomic) }
            if !session.failures.isEmpty { exit(1) }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
        }
    }
}
