// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
open System
open System.Diagnostics
let a=Environment.GetCommandLineArgs() |> Array.skip 1 |> Array.map int
let n,limit,warm,runs=a.[0],a.[1],a.[2],a.[3]
for run in -warm .. runs-1 do
    let start=Stopwatch.GetTimestamp()
    // PRIME-BEGIN: Allocate candidates
    // Create zero-filled candidate storage. Each slot represents an odd number; zero
    // means not yet marked composite.
    let flags=Array.zeroCreate<byte>(limit/2+1)
    let mutable p=3
    // PRIME-END
    // PRIME-BEGIN: Mark composites
    // Try odd divisors through the square root of the limit. Start at p squared; an
    // index step of p skips even multiples.
    while p<=limit/p do
        if flags.[p/2]=0uy then
            let mutable j=p*p/2
            while j<=limit/2 do
                flags.[j]<-1uy
                j<-j+p
        p<-p+2
    // PRIME-END
    // PRIME-BEGIN: Find the Nth prime
    // Count 2 as the first prime, then scan odd candidates. Stop when the requested
    // number of primes has been found.
    let mutable count=1
    let mutable last=2
    p<-3
    while count<n && p<=limit do
        if flags.[p/2]=0uy then
            count<-count+1
            last<-p
        p<-p+2
    // PRIME-END
    let ns=float(Stopwatch.GetTimestamp()-start)*1e9/float Stopwatch.Frequency
    let mutable sum=2L
    p<-3
    while p<=last do
        if flags.[p/2]=0uy then sum<-(sum+int64 p)%1000000007L
        p<-p+2
    if run>=0 then printfn "{\"elapsed_ns\":%.0f,\"count\":%d,\"last_prime\":%d,\"checksum\":%d}" ns count last sum
