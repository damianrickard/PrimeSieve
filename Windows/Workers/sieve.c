// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
static double now_ns(void) { LARGE_INTEGER value, frequency; QueryPerformanceCounter(&value); QueryPerformanceFrequency(&frequency); return (double)value.QuadPart * (1000000000.0 / (double)frequency.QuadPart); }
int main(int argc, char **argv) {
    if(argc!=5) return 2;
    uint64_t n=strtoull(argv[1],0,10), limit=strtoull(argv[2],0,10);
    int warm=atoi(argv[3]), runs=atoi(argv[4]);
    for(int run=-warm;run<runs;run++) {
        uint64_t start=now_ns();
        // PRIME-BEGIN: Allocate candidates
        // Create zero-filled candidate storage. Each slot represents an odd number; zero
        // means not yet marked composite.
        uint64_t count=1, last=2;
        unsigned char *flags=calloc(limit/2+1,1); if(!flags) return 3;
        // PRIME-END
        // PRIME-BEGIN: Mark composites
        // Try odd divisors through the square root of the limit. Start at p squared; an
        // index step of p skips even multiples.
        for(uint64_t p=3;p<=limit/p;p+=2) if(!flags[p/2])
            for(uint64_t j=p*p/2;j<=limit/2;j+=p) flags[j]=1;
        // PRIME-END
        // PRIME-BEGIN: Find the Nth prime
        // Count 2 as the first prime, then scan odd candidates. Stop when the requested
        // number of primes has been found.
        for(uint64_t p=3;count<n && p<=limit;p+=2) if(!flags[p/2]) { count++; last=p; }
        // PRIME-END
        uint64_t elapsed=now_ns()-start, sum=2;
        for(uint64_t p=3;p<=last;p+=2) if(!flags[p/2]) sum=(sum+p)%1000000007;
        free(flags);
        if(run>=0) printf("{\"elapsed_ns\":%llu,\"count\":%llu,\"last_prime\":%llu,\"checksum\":%llu}\n",(unsigned long long)elapsed,(unsigned long long)count,(unsigned long long)last,(unsigned long long)sum);
    }
}
