# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
n,limit,warm,runs=ARGV.map(&.to_i64)
(-warm...runs).each do |run|
 start=Time.monotonic
 # PRIME-BEGIN: Allocate candidates
 # Create zero-filled candidate storage. Each slot represents an odd number; zero means
 # not yet marked composite.
 flags=Bytes.new(limit//2+1,0_u8)
 p=3_i64
 # PRIME-END
 # PRIME-BEGIN: Mark composites
 # Try odd divisors through the square root of the limit. Start at p squared; an index
 # step of p skips even multiples.
 while p<=limit//p
  if flags[p//2]==0
   j=p*p//2
   while j<=limit//2;flags[j]=1_u8;j+=p;end
  end
  p+=2
 end
 # PRIME-END
 # PRIME-BEGIN: Find the Nth prime
 # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 # of primes has been found.
 count=1_i64;last=2_i64;p=3_i64
 while count<n && p<=limit
  if flags[p//2]==0;count+=1;last=p;end
  p+=2
 end
 # PRIME-END
 ns=(Time.monotonic-start).total_nanoseconds;sum=2_i64;p=3_i64
 while p<=last;sum=(sum+p)%1000000007 if flags[p//2]==0;p+=2;end
 puts %({"elapsed_ns":#{ns},"count":#{count},"last_prime":#{last},"checksum":#{sum}}) if run>=0
end
