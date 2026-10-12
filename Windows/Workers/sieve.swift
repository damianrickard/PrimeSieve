// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
import Foundation
import Dispatch
let args=CommandLine.arguments
let n=Int(args[1])!,limit=Int(args[2])!,warm=Int(args[3])!,runs=Int(args[4])!
for run in -warm..<runs {
    let start=DispatchTime.now().uptimeNanoseconds
    // PRIME-BEGIN: Allocate candidates
    // Create zero-filled candidate storage. Each slot represents an odd number; zero
    // means not yet marked composite.
    var flags=[UInt8](repeating:0,count:limit/2+1)
    var p=3
    // PRIME-END
    // PRIME-BEGIN: Mark composites
    // Try odd divisors through the square root of the limit. Start at p squared; an
    // index step of p skips even multiples.
    while p<=limit/p {
        if flags[p/2]==0 { var j=p*p/2; while j<=limit/2 { flags[j]=1;j+=p } }
        p+=2
    }
    // PRIME-END
    // PRIME-BEGIN: Find the Nth prime
    // Count 2 as the first prime, then scan odd candidates. Stop when the requested
    // number of primes has been found.
    var count=1,last=2;p=3
    while count<n && p<=limit { if flags[p/2]==0 {count+=1;last=p};p+=2 }
    // PRIME-END
    let elapsed=DispatchTime.now().uptimeNanoseconds-start
    var sum=2;p=3
    while p<=last {if flags[p/2]==0 {sum=(sum+p)%1_000_000_007};p+=2}
    if run>=0 {print("{\"elapsed_ns\":\(elapsed),\"count\":\(count),\"last_prime\":\(last),\"checksum\":\(sum)}")}
}
