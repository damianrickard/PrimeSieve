# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
import sys,time,json
n,limit,warm,runs=map(int,sys.argv[1:])
for run in range(-warm,runs):
    start=time.perf_counter_ns()
    # PRIME-BEGIN: Allocate candidates
    # Create zero-filled candidate storage. Each slot represents an odd number; zero
    # means not yet marked composite.
    flags=bytearray(limit//2+1)
    p=3
    # PRIME-END
    # PRIME-BEGIN: Mark composites
    # Try odd divisors through the square root of the limit. Start at p squared; an
    # index step of p skips even multiples.
    while p<=limit//p:
        if not flags[p//2]:
            j=p*p//2
            while j<=limit//2:
                flags[j]=1
                j+=p
        p+=2
    # PRIME-END
    # PRIME-BEGIN: Find the Nth prime
    # Count 2 as the first prime, then scan odd candidates. Stop when the requested
    # number of primes has been found.
    count,last,p=1,2,3
    while count<n and p<=limit:
        if not flags[p//2]: count,last=count+1,p
        p+=2
    # PRIME-END
    elapsed=time.perf_counter_ns()-start
    checksum=2
    for p in range(3,last+1,2):
        if not flags[p//2]: checksum=(checksum+p)%1000000007
    if run>=0: print(json.dumps(dict(elapsed_ns=elapsed,count=count,last_prime=last,checksum=checksum)),flush=True)
