// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
package main
import("fmt";"os";"strconv";"time")
func main(){a:=make([]int,4);for i:=range a{a[i],_=strconv.Atoi(os.Args[i+1])};n,limit,warm,runs:=a[0],a[1],a[2],a[3]
 for run:=-warm;run<runs;run++{
  start:=time.Now();
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  flags:=make([]byte,limit/2+1)
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  for p:=3;p<=limit/p;p+=2{if flags[p/2]==0{for j:=p*p/2;j<=limit/2;j+=p{flags[j]=1}}}
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  count,last:=1,2;for p:=3;count<n&&p<=limit;p+=2{if flags[p/2]==0{count++;last=p}}
  // PRIME-END
  elapsed:=time.Since(start).Nanoseconds();sum:=int64(2);for p:=3;p<=last;p+=2{if flags[p/2]==0{sum=(sum+int64(p))%1000000007}}
  if run>=0{fmt.Printf("{\"elapsed_ns\":%d,\"count\":%d,\"last_prime\":%d,\"checksum\":%d}\n",elapsed,count,last,sum)}
 }
}
