-- Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
-- The harness repeats warm-up and measured runs; only allocation, marking and scanning
-- are timed.
-- After timing, a modular checksum verifies the result and JSON reports each measured run.
local now=assert(package.loadlib('./clock.dll','luaopen_primesieve_clock'))()
local n,limit,warm,runs=tonumber(arg[1]),tonumber(arg[2]),tonumber(arg[3]),tonumber(arg[4])
for run=-warm,runs-1 do
 local start=now();
 -- PRIME-BEGIN: Allocate candidates
 -- Create zero-filled candidate storage. Each slot represents an odd number; zero means
 -- not yet marked composite. Lua stores these flags in a table.
 local flags={};for j=0,limit//2 do flags[j]=0 end
 -- PRIME-END
 -- PRIME-BEGIN: Mark composites
 -- Try odd divisors through the square root of the limit. Start at p squared; an index
 -- step of p skips even multiples.
 for p=3,math.floor(math.sqrt(limit)),2 do if flags[p//2]==0 then for j=p*p//2,limit//2,p do flags[j]=1 end end end
 -- PRIME-END
 -- PRIME-BEGIN: Find the Nth prime
 -- Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 -- of primes has been found.
 local count,last=1,2;local p=3
 while count<n and p<=limit do if flags[p//2]==0 then count=count+1;last=p end;p=p+2 end
 -- PRIME-END
 local elapsed=now()-start;local sum=2;for candidate=3,last,2 do if flags[candidate//2]==0 then sum=(sum+candidate)%1000000007 end end
 if run>=0 then print(string.format('{"elapsed_ns":%.0f,"count":%d,"last_prime":%d,"checksum":%d}',elapsed,count,last,sum)) end
end
