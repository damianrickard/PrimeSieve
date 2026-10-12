#!/usr/bin/env escript
%%! -noshell
% Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
% The harness repeats warm-up and measured runs; only allocation, marking and scanning
% are timed.
% After timing, a modular checksum verifies the result and JSON reports each measured run.
-mode(compile).
main(Args) ->
 [N,Lim,Warm,Runs]=lists:map(fun list_to_integer/1,Args),
 lists:foreach(fun(Run)->
  Start=erlang:monotonic_time(nanosecond),
  % PRIME-BEGIN: Run the calculation
  % Allocate candidates, mark composites, and scan for the requested final prime using
  % the helpers shown here.
  A=sieve(array:new(Lim div 2+1,[{default,0}]),3,Lim),
  {Count,Last}=scan(A,3,1,2,N),
  % PRIME-END
  NS=erlang:monotonic_time(nanosecond)-Start,
  Sum=sum(A,3,Last,2),
  case Run>=0 of true->io:format("{\"elapsed_ns\":~B,\"count\":~B,\"last_prime\":~B,\"checksum\":~B}~n",[NS,Count,Last,Sum]);false->ok end
 end,lists:seq(-Warm,Runs-1)).
% PRIME-BEGIN: Mark multiples
% Mark each remaining odd multiple as composite, returning the updated persistent array.
mark(A,J,_,Max) when J>Max -> A;
mark(A,J,P,Max) -> mark(array:set(J,1,A),J+P,P,Max).
% PRIME-END
% PRIME-BEGIN: Mark composites
% Try odd divisors through the square root of the limit. Start at p squared; an index
% step of p skips even multiples.
sieve(A,P,Lim) when P*P>Lim -> A;
sieve(A,P,Lim) ->
 B=case array:get(P div 2,A) of 0->mark(A,P*P div 2,P,Lim div 2);_->A end,
 sieve(B,P+2,Lim).
% PRIME-END
% PRIME-BEGIN: Find the Nth prime
% Count 2 as the first prime, then scan odd candidates. Stop when the requested number
% of primes has been found.
scan(_,_,Count,Last,N) when Count>=N -> {Count,Last};
scan(A,P,Count,Last,N) -> case array:get(P div 2,A) of 0->scan(A,P+2,Count+1,P,N);_->scan(A,P+2,Count,Last,N) end.
% PRIME-END
sum(_,P,Last,Sum) when P>Last -> Sum;
sum(A,P,Last,Sum) -> Next=case array:get(P div 2,A) of 0->(Sum+P) rem 1000000007;_->Sum end,sum(A,P+2,Last,Next).
