! Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
! The harness repeats warm-up and measured runs; only allocation, marking and scanning
! are timed.
! After timing, a modular checksum verifies the result and JSON reports each measured run.
program sieve
use iso_fortran_env, only:int8,int64
implicit none
integer(int64)::n,lim,p,j,found,last,total,t0,t1,rate
integer::warm,runs,run,k
character(40)::arg
integer(int8),allocatable::flags(:)
call get_command_argument(1,arg);read(arg,*)n
call get_command_argument(2,arg);read(arg,*)lim
call get_command_argument(3,arg);read(arg,*)warm
call get_command_argument(4,arg);read(arg,*)runs
call system_clock(count_rate=rate)
do run=-warm,runs-1
 call system_clock(t0)
 ! PRIME-BEGIN: Allocate candidates
 ! Create zero-filled candidate storage. Each slot represents an odd number; zero means
 ! not yet marked composite.
 allocate(flags(0:lim/2));flags=0
 p=3
 ! PRIME-END
 ! PRIME-BEGIN: Mark composites
 ! Try odd divisors through the square root of the limit. Start at p squared; an index
 ! step of p skips even multiples.
 do while(p<=lim/p)
  if(flags(p/2)==0)then
   j=p*p/2
   do while(j<=lim/2)
    flags(j)=1;j=j+p
   end do
  end if
  p=p+2
 end do
 ! PRIME-END
 ! PRIME-BEGIN: Find the Nth prime
 ! Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 ! of primes has been found.
 found=1;last=2;p=3
 do while(found<n.and.p<=lim)
  if(flags(p/2)==0)then
   found=found+1;last=p
  end if
  p=p+2
 end do
 ! PRIME-END
 call system_clock(t1)
 total=2;p=3
 do while(p<=last)
  if(flags(p/2)==0)total=modulo(total+p,1000000007_int64)
  p=p+2
 end do
 deallocate(flags)
 if(run>=0)then
  write(*,'(A,I0,A,I0,A,I0,A,I0,A)') &
   '{"elapsed_ns":',nint(real(t1-t0,8)*1e9/real(rate,8),int64),',"count":',found, &
   ',"last_prime":',last,',"checksum":',total,'}'
 end if
end do
end program
