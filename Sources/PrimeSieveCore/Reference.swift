import Foundation

public enum PrimeReference {
    /// Full-number sieve, independently implemented from the workers' odd-only sieve.
    public static func signature(count: Int, limit: Int) throws -> PrimeSignature {
        guard count > 0, limit >= 2, limit <= 200_000_000 else {
            throw BenchmarkError.message("Invalid reference workload.")
        }
        var composite = [Bool](repeating: false, count: limit + 1)
        var p = 2
        while p <= limit / p {
            try Task.checkCancellation()
            if !composite[p] {
                var multiple = p * p
                var iterations = 0
                while multiple <= limit {
                    if iterations.isMultiple(of: 16_384) { try Task.checkCancellation() }
                    composite[multiple] = true; multiple += p; iterations += 1
                }
            }
            p += 1
        }
        var found = 0, checksum = 0
        for candidate in 2...limit {
            if candidate.isMultiple(of: 8192) { try Task.checkCancellation() }
            if composite[candidate] { continue }
            found += 1
            checksum = (checksum + candidate) % 1_000_000_007
            if found == count { return .init(count: found, lastPrime: candidate, checksum: checksum) }
        }
        throw BenchmarkError.message("The common search bound did not contain enough primes.")
    }
}
