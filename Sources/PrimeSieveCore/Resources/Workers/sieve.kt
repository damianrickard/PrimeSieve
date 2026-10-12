// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
fun main(a:Array<String>){
 val n=a[0].toInt();val limit=a[1].toInt();val warm=a[2].toInt();val runs=a[3].toInt()
 for(run in -warm until runs){
  val start=System.nanoTime();
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  val flags=ByteArray(limit/2+1)
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  var p=3;while(p<=limit/p){if(flags[p/2].toInt()==0){var j=p*p/2;while(j<=limit/2){flags[j]=1;j+=p}};p+=2}
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  var count=1;var last=2;p=3;while(count<n&&p<=limit){if(flags[p/2].toInt()==0){count++;last=p};p+=2}
  // PRIME-END
  val elapsed=System.nanoTime()-start;var sum=2L;p=3;while(p<=last){if(flags[p/2].toInt()==0)sum=(sum+p)%1000000007;p+=2}
  if(run>=0)println("{\"elapsed_ns\":$elapsed,\"count\":$count,\"last_prime\":$last,\"checksum\":$sum}")
 }
}
