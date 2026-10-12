# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
n,limit,warm,runs=ARGV.map(&:to_i)
(-warm...runs).each do |run|
  start=Process.clock_gettime(Process::CLOCK_MONOTONIC,:nanosecond)
  # PRIME-BEGIN: Allocate candidates
  # Create zero-filled candidate storage. Each slot represents an odd number; zero means
  # not yet marked composite.
  flags="\0"*(limit/2+1)
  p=3
  # PRIME-END
  # PRIME-BEGIN: Mark composites
  # Try odd divisors through the square root of the limit. Start at p squared; an index
  # step of p skips even multiples.
  while p<=limit/p
    if flags.getbyte(p/2)==0
      j=p*p/2
      while j<=limit/2;flags.setbyte(j,1);j+=p;end
    end
    p+=2
  end
  # PRIME-END
  # PRIME-BEGIN: Find the Nth prime
  # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  # of primes has been found.
  count,last,p=1,2,3
  while count<n && p<=limit
    if flags.getbyte(p/2)==0;count+=1;last=p;end
    p+=2
  end
  # PRIME-END
  elapsed=Process.clock_gettime(Process::CLOCK_MONOTONIC,:nanosecond)-start
  sum,p=2,3
  while p<=last;sum=(sum+p)%1000000007 if flags.getbyte(p/2)==0;p+=2;end
  puts %Q({"elapsed_ns":#{elapsed},"count":#{count},"last_prime":#{last},"checksum":#{sum}}) if run>=0
end
