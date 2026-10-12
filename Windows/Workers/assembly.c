// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
static double now_ns(void) { LARGE_INTEGER value, frequency; QueryPerformanceCounter(&value); QueryPerformanceFrequency(&frequency); return (double)value.QuadPart * (1000000000.0 / (double)frequency.QuadPart); }
extern uint64_t sieve_kernel(unsigned char *, uint64_t, uint64_t);
int main(int argc, char **argv) {
    if(argc!=5) return 2;
    uint64_t n=strtoull(argv[1],0,10), limit=strtoull(argv[2],0,10);
    int warm=atoi(argv[3]), runs=atoi(argv[4]);
    for(int run=-warm;run<runs;run++) {
        uint64_t start=now_ns();
        // PRIME-BEGIN: Run the calculation
        // Allocate candidates, mark composites, and scan for the requested final prime
        // using the helpers shown here.
        uint64_t count=1, last=2;
        unsigned char *flags=calloc(limit/2+1,1); if(!flags) return 3;
        last=sieve_kernel(flags,limit,n); count=last ? n : 0;
        // PRIME-END
        uint64_t elapsed=now_ns()-start, sum=2;
        for(uint64_t p=3;p<=last;p+=2) if(!flags[p/2]) sum=(sum+p)%1000000007;
        free(flags);
        if(run>=0) printf("{\"elapsed_ns\":%llu,\"count\":%llu,\"last_prime\":%llu,\"checksum\":%llu}\n",(unsigned long long)elapsed,(unsigned long long)count,(unsigned long long)last,(unsigned long long)sum);
    }
}
