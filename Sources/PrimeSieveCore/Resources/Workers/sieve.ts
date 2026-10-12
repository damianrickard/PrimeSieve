// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
declare const process: any;
const [n,limit,warm,runs]=process.argv.slice(2).map(Number);
for(let run=-warm;run<runs;run++) {
    const start=process.hrtime.bigint();
    // PRIME-BEGIN: Allocate candidates
    // Create zero-filled candidate storage. Each slot represents an odd number; zero
    // means not yet marked composite.
    const flags=new Uint8Array(Math.floor(limit/2)+1);
    // PRIME-END
    // PRIME-BEGIN: Mark composites
    // Try odd divisors through the square root of the limit. Start at p squared; an
    // index step of p skips even multiples.
    for(let p=3;p<=Math.floor(limit/p);p+=2)if(!flags[p>>1])for(let j=(p*p)>>1;j<=limit>>1;j+=p)flags[j]=1;
    // PRIME-END
    // PRIME-BEGIN: Find the Nth prime
    // Count 2 as the first prime, then scan odd candidates. Stop when the requested
    // number of primes has been found.
    let count=1,last=2;
    for(let p=3;count<n&&p<=limit;p+=2)if(!flags[p>>1]){count++;last=p;}
    // PRIME-END
    const elapsed=Number(process.hrtime.bigint()-start);
    let checksum=2;for(let p=3;p<=last;p+=2)if(!flags[p>>1])checksum=(checksum+p)%1000000007;
    if(run>=0)console.log(JSON.stringify({elapsed_ns:elapsed,count,last_prime:last,checksum}));
}
