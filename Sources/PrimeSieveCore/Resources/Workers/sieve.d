// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
import std.conv,std.stdio,core.time;
void main(string[] a){
 auto n=to!long(a[1]),limit=to!long(a[2]);auto warm=to!int(a[3]),runs=to!int(a[4]);
 foreach(run;-warm..runs){
  auto start=MonoTime.currTime;
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  auto flags=new ubyte[limit/2+1];
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  for(long p=3;p<=limit/p;p+=2)if(!flags[p/2])for(long j=p*p/2;j<=limit/2;j+=p)flags[j]=1;
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  long count=1,last=2;for(long p=3;count<n&&p<=limit;p+=2)if(!flags[p/2]){count++;last=p;}
  // PRIME-END
  auto ns=(MonoTime.currTime-start).total!"nsecs";long sum=2;for(long p=3;p<=last;p+=2)if(!flags[p/2])sum=(sum+p)%1000000007;
  if(run>=0)writefln("{\"elapsed_ns\":%s,\"count\":%s,\"last_prime\":%s,\"checksum\":%s}",ns,count,last,sum);
 }
}
