<?php
// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
[$n,$limit,$warm,$runs]=array_map('intval',array_slice($argv,1));
for($run=-$warm;$run<$runs;$run++){
 $start=hrtime(true);
 // PRIME-BEGIN: Allocate candidates
 // Create zero-filled candidate storage. Each slot represents an odd number; zero means
 // not yet marked composite.
 $flags=str_repeat("\0",intdiv($limit,2)+1);
 // PRIME-END
 // PRIME-BEGIN: Mark composites
 // Try odd divisors through the square root of the limit. Start at p squared; an index
 // step of p skips even multiples.
 for($p=3;$p<=intdiv($limit,$p);$p+=2)if(ord($flags[intdiv($p,2)])==0)for($j=intdiv($p*$p,2);$j<=intdiv($limit,2);$j+=$p)$flags[$j]="\1";
 // PRIME-END
 // PRIME-BEGIN: Find the Nth prime
 // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 // of primes has been found.
 $count=1;$last=2;for($p=3;$count<$n&&$p<=$limit;$p+=2)if(ord($flags[intdiv($p,2)])==0){$count++;$last=$p;}
 // PRIME-END
 $elapsed=hrtime(true)-$start;$sum=2;for($p=3;$p<=$last;$p+=2)if(ord($flags[intdiv($p,2)])==0)$sum=($sum+$p)%1000000007;
 if($run>=0)echo json_encode(['elapsed_ns'=>$elapsed,'count'=>$count,'last_prime'=>$last,'checksum'=>$sum])."\n";
}
