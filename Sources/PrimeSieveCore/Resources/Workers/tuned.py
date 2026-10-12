"""Protocol 3: n limit warm samples mode seconds workload variant full_sequence.
Fresh storage on every pass. Throughput retains the last measured sieve and verifies
it after the window. No verification or prime scanning occurs inside that window.
"""
import json
import sys
import time
from math import isqrt

n, limit, warm, runs = map(int, sys.argv[1:5])
mode, seconds, workload, variant, full = sys.argv[5:10]
seconds = float(seconds)

# PRIME-BEGIN: Allocate and mark composites
# One byte per odd candidate. Slice assignment executes marking in the runtime.
def sieve():
    flags = bytearray(limit // 2 + 1)
    flags[0] = 1  # one is not prime
    for prime in range(3, isqrt(limit) + 1, 2):
        if not flags[prime // 2]:
            start = prime * prime // 2
            flags[start::prime] = b'\x01' * ((len(flags) - 1 - start) // prime + 1)
    return flags
# PRIME-END

# PRIME-BEGIN: Find the requested primes
# Built-in byte search skips runs of composites. Bound the last odd candidate.
def primes(flags):
    yield 2
    index = 1
    end = (limit + 1) // 2
    while index < end:
        index = flags.find(b'\x00', index, end)
        if index < 0:
            break
        yield 2 * index + 1
        index += 1

def scan(flags):
    found, last = 0, 0
    for prime in primes(flags):
        found += 1
        last = prime
        if found == n:
            break
    return found, last
# PRIME-END

for _ in range(warm):
    flags = sieve()
    if mode != 'throughput':
        scan(flags)
# Do not carry a warm-up buffer into a measured window.
flags = None
for _ in range(runs):
    passes = 0
    observation = 0
    start = time.perf_counter_ns()
    while True:
        flags = sieve()
        if mode == 'throughput':
            observation ^= flags[passes % len(flags)]
        passes += 1
        if mode != 'throughput':
            found, last = scan(flags)
        elapsed = time.perf_counter_ns() - start
        if mode != 'throughput' or elapsed >= seconds * 1e9:
            break
    if mode == 'throughput':
        found, last = scan(flags)
    sequence = []
    checksum = 0
    for prime in primes(flags):
        if prime > last:
            break
        checksum = (checksum + prime) % 1_000_000_007
        if full == '1':
            sequence.append(prime)
    result = dict(elapsed_ns=elapsed, count=found, last_prime=last,
                  checksum=checksum, passes=passes, observation=observation)
    if full == '1':
        result['primes'] = sequence
    print(json.dumps(result), flush=True)
    flags = None
