// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
import groovy.transform.CompileStatic
@CompileStatic
class Sieve {
 static void main(String[] a){
  int n=a[0].toInteger(),limit=a[1].toInteger(),warm=a[2].toInteger(),runs=a[3].toInteger()
  for(int run=-warm;run<runs;run++){
   long start=System.nanoTime();
   // PRIME-BEGIN: Allocate candidates
   // Create zero-filled candidate storage. Each slot represents an odd number; zero
   // means not yet marked composite.
   byte[] flags=new byte[limit.intdiv(2)+1]
   // PRIME-END
   // PRIME-BEGIN: Mark composites
   // Try odd divisors through the square root of the limit. Start at p squared; an index
   // step of p skips even multiples.
   for(int p=3;p<=limit.intdiv(p);p+=2)if(flags[p.intdiv(2)]==0)for(int j=(p*p).intdiv(2);j<=limit.intdiv(2);j+=p)flags[j]=1
   // PRIME-END
   // PRIME-BEGIN: Find the Nth prime
   // Count 2 as the first prime, then scan odd candidates. Stop when the requested
   // number of primes has been found.
   int count=1,last=2;for(int p=3;count<n&&p<=limit;p+=2)if(flags[p.intdiv(2)]==0){count++;last=p}
   // PRIME-END
   long elapsed=System.nanoTime()-start,sum=2;for(int p=3;p<=last;p+=2)if(flags[p.intdiv(2)]==0)sum=(sum+p)%1000000007L
   if(run>=0)println("{\"elapsed_ns\":${elapsed},\"count\":${count},\"last_prime\":${last},\"checksum\":${sum}}")
  }
 }
}
