// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
const std=@import("std");
extern "c" fn calloc(usize,usize) ?*anyopaque;
extern "c" fn free(?*anyopaque) void;
extern "c" fn strtol([*:0]const u8,?*anyopaque,c_int) c_long;
extern "c" fn printf([*:0]const u8,...) c_int;
extern "c" fn primesieve_now() f64;
fn now() u64 { return @intFromFloat(primesieve_now()); }
pub export fn main(argc:c_int,argv:[*][*:0]const u8)c_int{
 if(argc!=5)return 2;
 const n:usize=@intCast(strtol(argv[1],null,10));const limit:usize=@intCast(strtol(argv[2],null,10));
 const warm=strtol(argv[3],null,10);const runs=strtol(argv[4],null,10);
 var run:c_long=-warm;
 while(run<runs):(run+=1){
  const start=now();
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  const allocation=calloc(limit/2+1,1) orelse return 3;
  const flags:[*]u8=@ptrCast(allocation);var p:usize=3;
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  while(p<=limit/p):(p+=2){if(flags[p/2]==0){var j=p*p/2;while(j<=limit/2):(j+=p){flags[j]=1;}}}
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  var count:usize=1;var last:usize=2;p=3;
  while(count<n and p<=limit):(p+=2){if(flags[p/2]==0){count+=1;last=p;}}
  // PRIME-END
  const elapsed=now()-start;var sum:usize=2;p=3;
  while(p<=last):(p+=2){if(flags[p/2]==0){sum=(sum+p)%1000000007;}}
  free(allocation);
  if(run>=0){_=printf("{\"elapsed_ns\":%llu,\"count\":%llu,\"last_prime\":%llu,\"checksum\":%llu}\n",@as(c_ulonglong,elapsed),@as(c_ulonglong,count),@as(c_ulonglong,last),@as(c_ulonglong,sum));}
 }
 return 0;
}
