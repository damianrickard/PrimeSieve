// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
using System;using System.Diagnostics;
class Sieve {
 static void Main(string[] a){
 int n=int.Parse(a[0]),limit=int.Parse(a[1]),warm=int.Parse(a[2]),runs=int.Parse(a[3]);
 for(int run=-warm;run<runs;run++){
  long start=Stopwatch.GetTimestamp();
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  var flags=new byte[limit/2+1];
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  for(int p=3;p<=limit/p;p+=2)if(flags[p/2]==0)for(int j=p*p/2;j<=limit/2;j+=p)flags[j]=1;
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  int count=1,last=2;for(int p=3;count<n&&p<=limit;p+=2)if(flags[p/2]==0){count++;last=p;}
  // PRIME-END
  double ns=(Stopwatch.GetTimestamp()-start)*1e9/Stopwatch.Frequency;long sum=2;
  for(int p=3;p<=last;p+=2)if(flags[p/2]==0)sum=(sum+p)%1000000007;
  if(run>=0)Console.WriteLine(FormattableString.Invariant($"{{\"elapsed_ns\":{ns},\"count\":{count},\"last_prime\":{last},\"checksum\":{sum}}}"));
 }
 }
}
