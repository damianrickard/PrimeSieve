# Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
# The harness repeats warm-up and measured runs; only allocation, marking and scanning
# are timed.
# After timing, a modular checksum verifies the result and JSON reports each measured run.
use strict;use warnings;use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);
my($n,$limit,$warm,$runs)=@ARGV;
for(my $run=-$warm;$run<$runs;$run++){
 my $start=clock_gettime(CLOCK_MONOTONIC);
 # PRIME-BEGIN: Allocate candidates
 # Create zero-filled candidate storage. Each slot represents an odd number; zero means
 # not yet marked composite.
 my $flags="\0" x (int($limit/2)+1);
 # PRIME-END
 # PRIME-BEGIN: Mark composites
 # Try odd divisors through the square root of the limit. Start at p squared; an index
 # step of p skips even multiples.
 for(my $p=3;$p<=int($limit/$p);$p+=2){if(!vec($flags,int($p/2),8)){for(my $j=int($p*$p/2);$j<=int($limit/2);$j+=$p){vec($flags,$j,8)=1;}}}
 # PRIME-END
 # PRIME-BEGIN: Find the Nth prime
 # Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 # of primes has been found.
 my($count,$last)=(1,2);
 for(my $p=3;$count<$n&&$p<=$limit;$p+=2){if(!vec($flags,int($p/2),8)){$count++;$last=$p;}}
 # PRIME-END
 my $elapsed=(clock_gettime(CLOCK_MONOTONIC)-$start)*1e9;
 my $sum=2;for(my $p=3;$p<=$last;$p+=2){$sum=($sum+$p)%1000000007 if !vec($flags,int($p/2),8);}
 print "{\"elapsed_ns\":$elapsed,\"count\":$count,\"last_prime\":$last,\"checksum\":$sum}\n" if $run>=0;
}
