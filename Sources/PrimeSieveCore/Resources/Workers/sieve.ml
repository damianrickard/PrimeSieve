(* Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound). *)
(* The harness repeats warm-up and measured runs; only allocation, marking and scanning *)
(* are timed. *)
(* After timing, a modular checksum verifies the result and JSON reports each measured run. *)
external now : unit -> float = "primesieve_monotonic"
let () =
 let n=int_of_string Sys.argv.(1) and lim=int_of_string Sys.argv.(2) and warm=int_of_string Sys.argv.(3) and runs=int_of_string Sys.argv.(4) in
 for run= -warm to runs-1 do
  let start=now() in
  (* PRIME-BEGIN: Allocate candidates *)
  (* Create zero-filled candidate storage. Each slot represents an odd number; zero means *)
  (* not yet marked composite. *)
  let flags=Bytes.make (lim/2+1) '\000' in
  let p=ref 3 in
  (* PRIME-END *)
  (* PRIME-BEGIN: Mark composites *)
  (* Try odd divisors through the square root of the limit. Start at p squared; an index *)
  (* step of p skips even multiples. *)
  while !p<=lim/ !p do
   if Bytes.get flags (!p/2)='\000' then (let j=ref (!p * !p/2) in while !j<=lim/2 do Bytes.set flags !j '\001';j := !j+ !p done);
   p := !p+2
  done;
  (* PRIME-END *)
  (* PRIME-BEGIN: Find the Nth prime *)
  (* Count 2 as the first prime, then scan odd candidates. Stop when the requested number *)
  (* of primes has been found. *)
  let count=ref 1 and last=ref 2 in p:=3;
  while !count<n && !p<=lim do if Bytes.get flags (!p/2)='\000' then (incr count;last:= !p);p := !p+2 done;
  (* PRIME-END *)
  let ns=now()-.start in
  let sum=ref 2 in p:=3;
  while !p<= !last do if Bytes.get flags (!p/2)='\000' then sum := (!sum+ !p) mod 1000000007;p := !p+2 done;
  if run>=0 then Printf.printf "{\"elapsed_ns\":%.0f,\"count\":%d,\"last_prime\":%d,\"checksum\":%d}\n%!" ns !count !last !sum
 done
