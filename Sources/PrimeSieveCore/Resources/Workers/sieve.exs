# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
defmodule Sieve do
 # PRIME-BEGIN: Mark multiples
 # Mark each remaining odd multiple as composite, returning the updated persistent array.
 def mark(a,j,p,max) when j>max, do: a
 def mark(a,j,p,max), do: mark(:array.set(j,1,a),j+p,p,max)
 # PRIME-END
 # PRIME-BEGIN: Mark composites
 # Try odd divisors through the square root of the limit. Start at p squared; an index
 # step of p skips even multiples.
 def sieve(a,p,lim) when p*p>lim, do: a
 def sieve(a,p,lim) do
  a=if :array.get(div(p,2),a)==0, do: mark(a,div(p*p,2),p,div(lim,2)), else: a
  sieve(a,p+2,lim)
 end
 # PRIME-END
 # PRIME-BEGIN: Find the Nth prime
 # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 # of primes has been found.
 def scan(_,_,count,last,n) when count>=n, do: {count,last}
 def scan(a,p,count,last,n) do
  if :array.get(div(p,2),a)==0, do: scan(a,p+2,count+1,p,n), else: scan(a,p+2,count,last,n)
 end
 # PRIME-END
 def sum(_,p,last,total) when p>last, do: total
 def sum(a,p,last,total) do
  next=if :array.get(div(p,2),a)==0, do: rem(total+p,1_000_000_007), else: total
  sum(a,p+2,last,next)
 end
 def run(n,lim,warm,runs) do
  for run <- -warm..(runs-1) do
   start=System.monotonic_time(:nanosecond)
   # PRIME-BEGIN: Run the calculation
   # Allocate candidates, mark composites, and scan for the requested final prime using
   # the helpers shown here.
   a=sieve(:array.new(div(lim,2)+1,default: 0),3,lim)
   {count,last}=scan(a,3,1,2,n)
   # PRIME-END
   ns=System.monotonic_time(:nanosecond)-start
   total=sum(a,3,last,2)
   if run>=0, do: IO.puts("{\"elapsed_ns\":#{ns},\"count\":#{count},\"last_prime\":#{last},\"checksum\":#{total}}")
  end
 end
end
[n,lim,warm,runs]=Enum.map(System.argv(),&String.to_integer/1)
Sieve.run(n,lim,warm,runs)
