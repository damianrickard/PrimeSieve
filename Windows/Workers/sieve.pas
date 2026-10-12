// Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
// The harness repeats warm-up and measured runs; only allocation, marking and scanning
// are timed.
// After timing, a modular checksum verifies the result and JSON reports each measured run.
program PrimeSieve;
{$mode objfpc}
uses SysUtils, Windows;
function NowNS:QWord;var ticks,frequency:Int64;begin QueryPerformanceCounter(ticks);QueryPerformanceFrequency(frequency);NowNS:=Round(ticks*(1000000000.0/frequency));end;
var n,lim,p,j,count,last,sum,start,elapsed:QWord;warm,runs,run:LongInt;flags:array of Byte;
begin
 n:=StrToQWord(ParamStr(1));lim:=StrToQWord(ParamStr(2));warm:=StrToInt(ParamStr(3));runs:=StrToInt(ParamStr(4));
 for run:=-warm to runs-1 do begin
  start:=NowNS;
  // PRIME-BEGIN: Allocate candidates
  // Create zero-filled candidate storage. Each slot represents an odd number; zero means
  // not yet marked composite.
  SetLength(flags,0);SetLength(flags,lim div 2+1);
  // PRIME-END
  // PRIME-BEGIN: Mark composites
  // Try odd divisors through the square root of the limit. Start at p squared; an index
  // step of p skips even multiples.
  p:=3;while p<=lim div p do begin
   if flags[p div 2]=0 then begin j:=p*p div 2;while j<=lim div 2 do begin flags[j]:=1;j:=j+p;end;end;
   p:=p+2;
  end;
  // PRIME-END
  // PRIME-BEGIN: Find the Nth prime
  // Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  // of primes has been found.
  count:=1;last:=2;p:=3;while (count<n)and(p<=lim)do begin if flags[p div 2]=0 then begin Inc(count);last:=p;end;p:=p+2;end;
  // PRIME-END
  elapsed:=NowNS-start;sum:=2;p:=3;while p<=last do begin if flags[p div 2]=0 then sum:=(sum+p)mod 1000000007;p:=p+2;end;
  if run>=0 then WriteLn('{"elapsed_ns":',elapsed,',"count":',count,',"last_prime":',last,',"checksum":',sum,'}');
 end;
end.
