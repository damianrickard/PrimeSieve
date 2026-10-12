# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
import std/[os,strutils,monotimes,times]
let n=parseInt(paramStr(1));let limit=parseInt(paramStr(2));let warm=parseInt(paramStr(3));let runs=parseInt(paramStr(4))
for run in -warm..<runs:
 let start=getMonoTime()
 # PRIME-BEGIN: Allocate candidates
 # Create zero-filled candidate storage. Each slot represents an odd number; zero means
 # not yet marked composite.
 var flags=newSeq[uint8](limit div 2+1)
 var p=3
 # PRIME-END
 # PRIME-BEGIN: Mark composites
 # Try odd divisors through the square root of the limit. Start at p squared; an index
 # step of p skips even multiples.
 while p<=limit div p:
  if flags[p div 2]==0:
   var j=p*p div 2
   while j<=limit div 2:
    flags[j]=1;j+=p
  p+=2
 # PRIME-END
 # PRIME-BEGIN: Find the Nth prime
 # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 # of primes has been found.
 var count=1;var last=2;p=3
 while count<n and p<=limit:
  if flags[p div 2]==0:count+=1;last=p
  p+=2
 # PRIME-END
 let ns=(getMonoTime()-start).inNanoseconds
 var sum=2;p=3
 while p<=last:
  if flags[p div 2]==0:sum=(sum+p) mod 1000000007
  p+=2
 if run>=0:echo "{\"elapsed_ns\":",ns,",\"count\":",count,",\"last_prime\":",last,",\"checksum\":",sum,"}"
