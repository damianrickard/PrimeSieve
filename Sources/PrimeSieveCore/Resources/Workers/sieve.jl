# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
function benchmark(n,limit,warm,runs)
 for run in -warm:runs-1
  start=time_ns();
  # PRIME-BEGIN: Allocate candidates
  # Create zero-filled candidate storage. Each slot represents an odd number; zero means
  # not yet marked composite. This language uses one-based indices, so add one to the
  # odd-number index.
  flags=zeros(UInt8,limit÷2+1)
  p=3
  # PRIME-END
  # PRIME-BEGIN: Mark composites
  # Try odd divisors through the square root of the limit. Start at p squared; an index
  # step of p skips even multiples.
  while p<=limit÷p
   if flags[p÷2+1]==0
    j=p*p÷2
    while j<=limit÷2;flags[j+1]=1;j+=p;end
   end
   p+=2
  end
  # PRIME-END
  # PRIME-BEGIN: Find the Nth prime
  # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  # of primes has been found.
  count=1;last=2;p=3
  while count<n&&p<=limit
   if flags[p÷2+1]==0;count+=1;last=p;end
   p+=2
  end
  # PRIME-END
  ns=time_ns()-start;sum=2;p=3
  while p<=last;if flags[p÷2+1]==0;sum=(sum+p)%1000000007;end;p+=2;end
  if run>=0;println("{\"elapsed_ns\":$ns,\"count\":$count,\"last_prime\":$last,\"checksum\":$sum}");end
 end
end
benchmark(parse.(Int,ARGS)...)
