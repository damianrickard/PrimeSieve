# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
args<-as.numeric(commandArgs(trailingOnly=TRUE));n<-args[1];limit<-args[2];warm<-args[3];runs<-args[4]
dyn.load("clock.dylib");now<-function() .C("primesieve_clock",out=double(1))$out
for(run in seq.int(-warm,runs-1)){
 start<-now();
 # PRIME-BEGIN: Allocate candidates
 # Create zero-filled candidate storage. Each slot represents an odd number; zero means
 # not yet marked composite. This language uses one-based indices, so add one to the
 # odd-number index.
 flags<-raw(floor(limit/2)+1);p<-3
 # PRIME-END
 # PRIME-BEGIN: Mark composites
 # Try odd divisors through the square root of the limit. Start at p squared; an index
 # step of p skips even multiples.
 while(p<=floor(limit/p)){
  if(flags[floor(p/2)+1]==as.raw(0)){j<-floor(p*p/2);while(j<=floor(limit/2)){flags[j+1]<-as.raw(1);j<-j+p}}
  p<-p+2
 }
 # PRIME-END
 # PRIME-BEGIN: Find the Nth prime
 # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 # of primes has been found.
 count<-1;last<-2;p<-3
 while(count<n&&p<=limit){if(flags[floor(p/2)+1]==as.raw(0)){count<-count+1;last<-p};p<-p+2}
 # PRIME-END
 elapsed<-now()-start;sum<-2;p<-3
 while(p<=last){if(flags[floor(p/2)+1]==as.raw(0))sum<-(sum+p)%%1000000007;p<-p+2}
 if(run>=0)cat(sprintf('{"elapsed_ns":%.0f,"count":%.0f,"last_prime":%.0f,"checksum":%.0f}\n',elapsed,count,last,sum))
}
