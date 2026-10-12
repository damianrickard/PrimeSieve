// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>
int main(int argc,char**argv) {
    if(argc!=5)return 2;
    uint64_t n=std::strtoull(argv[1],nullptr,10),limit=std::strtoull(argv[2],nullptr,10);
    for(int run=-std::atoi(argv[3]);run<std::atoi(argv[4]);++run) {
        auto start=std::chrono::steady_clock::now();
        // PRIME-BEGIN: Allocate candidates
        // Create zero-filled candidate storage. Each slot represents an odd number; zero
        // means not yet marked composite.
        std::vector<uint8_t> flags(limit/2+1,0);
        // PRIME-END
        // PRIME-BEGIN: Mark composites
        // Try odd divisors through the square root of the limit. Start at p squared; an
        // index step of p skips even multiples.
        for(uint64_t p=3;p<=limit/p;p+=2)if(!flags[p/2])for(uint64_t j=p*p/2;j<=limit/2;j+=p)flags[j]=1;
        // PRIME-END
        // PRIME-BEGIN: Find the Nth prime
        // Count 2 as the first prime, then scan odd candidates. Stop when the requested
        // number of primes has been found.
        uint64_t count=1,last=2;
        for(uint64_t p=3;count<n&&p<=limit;p+=2)if(!flags[p/2]){++count;last=p;}
        // PRIME-END
        auto ns=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now()-start).count();
        uint64_t sum=2;for(uint64_t p=3;p<=last;p+=2)if(!flags[p/2])sum=(sum+p)%1000000007;
        if(run>=0)std::printf("{\"elapsed_ns\":%lld,\"count\":%llu,\"last_prime\":%llu,\"checksum\":%llu}\n",(long long)ns,(unsigned long long)count,(unsigned long long)last,(unsigned long long)sum);
    }
}
