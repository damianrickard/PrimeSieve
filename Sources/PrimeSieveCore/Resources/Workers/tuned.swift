import Foundation
import Dispatch

// Protocol 3. All variants own fresh storage. A measured result is retained for
// independent checking after timing. The observation keeps every pass observable.
let arguments = Array(CommandLine.arguments.dropFirst())
let n = Int(arguments[0])!, limit = Int(arguments[1])!
let warm = Int(arguments[2])!, runs = Int(arguments[3])!
let throughput = arguments[4] == "throughput"
let duration = UInt64(Double(arguments[5])! * 1e9)
let variant = arguments[7], full = arguments[8] == "1"

final class Sieve {
    let flags: UnsafeMutablePointer<UInt8>
    let candidates: Int
    let size: Int
    let striped: Bool
    let packed: Bool
    let planeLength: Int
    // PRIME-BEGIN: Allocate candidates
    init() {
        candidates = limit / 2 + 1
        packed = variant != "byte"
        striped = variant == "striped"
        size = packed ? (candidates + 7) / 8 : candidates
        planeLength = size
        flags = .allocate(capacity: size)
        flags.initialize(repeating: 0, count: size)
        mark(0)
    }
    deinit { flags.deallocate() }
    @inline(__always) func composite(_ i: Int) -> Bool {
        if !packed { return flags[i] != 0 }
        if striped { return flags[i % planeLength] & (UInt8(1) << (i / planeLength)) != 0 }
        return flags[i >> 3] & (UInt8(1) << (i & 7)) != 0
    }
    @inline(__always) func mark(_ i: Int) {
        if !packed { flags[i] = 1 }
        else if striped { flags[i % planeLength] |= UInt8(1) << (i / planeLength) }
        else { flags[i >> 3] |= UInt8(1) << (i & 7) }
    }
    // PRIME-END
    // PRIME-BEGIN: Mark composites
    // Stripes keep a constant bit mask while marking a contiguous plane of bytes.
    @inline(never) func run() {
        var p = 3
        while p <= limit / p {
            if !composite(p / 2) {
                var j = p * p / 2
                if striped {
                    while j < candidates {
                        let plane = j / planeLength
                        let end = min(candidates, (plane + 1) * planeLength)
                        let mask = UInt8(1) << plane
                        var offset = j - plane * planeLength
                        let stop = end - plane * planeLength
                        while offset + 7 * p < stop {
                            flags[offset] |= mask; flags[offset + p] |= mask
                            flags[offset + 2*p] |= mask; flags[offset + 3*p] |= mask
                            flags[offset + 4*p] |= mask; flags[offset + 5*p] |= mask
                            flags[offset + 6*p] |= mask; flags[offset + 7*p] |= mask
                            offset += 8*p
                        }
                        while offset < stop { flags[offset] |= mask; offset += p }
                        j = plane * planeLength + offset
                    }
                } else {
                    while j < candidates { mark(j); j += p }
                }
            }
            p += 2
        }
    }
    // PRIME-END
    // PRIME-BEGIN: Find the Nth prime
    func scan() -> (Int, Int) {
        var count = 1, last = 2, p = 3
        while count < n && p <= limit {
            if !composite(p / 2) { count += 1; last = p }
            p += 2
        }
        return (count, last)
    }
    // PRIME-END
    @inline(never) func observe(_ index: Int) -> UInt8 { flags[index % size] }
}
for _ in 0..<warm { let sieve = Sieve(); sieve.run(); if !throughput { _ = sieve.scan() } }
for _ in 0..<runs {
    var retained: Sieve?
    var passes = 0, count = 0, last = 0
    var observation: UInt8 = 0
    let start = DispatchTime.now().uptimeNanoseconds
    var elapsed: UInt64 = 0
    repeat {
        let sieve = Sieve(); sieve.run()
        if throughput { observation ^= sieve.observe(passes) }
        retained = sieve
        passes += 1
        if !throughput { (count, last) = sieve.scan() }
        elapsed = DispatchTime.now().uptimeNanoseconds - start
    } while throughput && elapsed < duration
    let sieve = retained!
    if throughput { (count, last) = sieve.scan() }
    var sum = 2, sequence = [2], p = 3
    while p <= last {
        if !sieve.composite(p / 2) {
            sum = (sum + p) % 1_000_000_007
            if full { sequence.append(p) }
        }
        p += 2
    }
    var output: [String: Any] = ["elapsed_ns": elapsed, "passes": passes, "count": count,
                               "last_prime": last, "checksum": sum, "observation": observation]
    if full { output["primes"] = sequence }
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
