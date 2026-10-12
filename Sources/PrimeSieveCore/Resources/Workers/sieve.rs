// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
use std::{env,time::Instant};
fn main(){
 let a:Vec<usize>=env::args().skip(1).map(|x|x.parse().unwrap()).collect();
 let(n,limit,warm,runs)=(a[0],a[1],a[2],a[3]);
 for run in 0..warm+runs{
  let start=Instant::now();
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  let mut flags=vec![0u8;limit/2+1];let mut p=3;
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  while p<=limit/p{if flags[p/2]==0{let mut j=p*p/2;while j<=limit/2{flags[j]=1;j+=p;}}p+=2;}
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  let(mut count,mut last)=(1,2);p=3;
  while count<n&&p<=limit{if flags[p/2]==0{count+=1;last=p;}p+=2;}
  // PRIME-END
  let elapsed=start.elapsed().as_nanos();let mut sum=2usize;p=3;
  while p<=last{if flags[p/2]==0{sum=(sum+p)%1_000_000_007;}p+=2;}
  if run>=warm{println!("{{\"elapsed_ns\":{},\"count\":{},\"last_prime\":{},\"checksum\":{}}}",elapsed,count,last,sum);}
 }
}
