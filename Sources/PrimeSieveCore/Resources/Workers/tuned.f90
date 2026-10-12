! Protocol 3. Byte and packed-bit variants, fresh allocation per pass.
module sieve_state
 use iso_fortran_env, only: int8,int64
 implicit none
 integer(int64) :: n,lim
 logical :: packed
contains
 ! PRIME-BEGIN: Allocate and mark composites
 subroutine make_sieve(flags)
  integer(int8),allocatable,intent(out) :: flags(:)
  integer(int64) :: p,j,size
  size=lim/2+1
  if(packed) size=(size+7)/8
  allocate(flags(0:size-1));flags=0
  call mark(flags,0_int64)
  p=3
  do while(p<=lim/p)
   if(.not.composite(flags,p/2)) then
    j=p*p/2
    do while(j<=lim/2)
     call mark(flags,j);j=j+p
    end do
   end if
   p=p+2
  end do
 end subroutine
 subroutine mark(flags,i)
  integer(int8),intent(inout)::flags(0:)
  integer(int64),intent(in)::i
  if(packed) then
   flags(i/8)=ibset(flags(i/8),int(modulo(i,8_int64)))
  else
   flags(i)=1
  end if
 end subroutine
 logical function composite(flags,i)
  integer(int8),intent(in)::flags(0:)
  integer(int64),intent(in)::i
  if(packed) then
   composite=btest(flags(i/8),int(modulo(i,8_int64)))
  else
   composite=flags(i)/=0
  end if
 end function
 ! PRIME-END
 ! PRIME-BEGIN: Find the Nth prime
 subroutine scan(flags,count,last)
  integer(int8),intent(in)::flags(0:)
  integer(int64),intent(out)::count,last
  integer(int64)::p
  count=1;last=2;p=3
  do while(count<n.and.p<=lim)
   if(.not.composite(flags,p/2))then
    count=count+1;last=p
   end if
   p=p+2
  end do
 end subroutine
 ! PRIME-END
end module
program benchmark
 use sieve_state
 implicit none
 integer(int8),allocatable::flags(:),next(:)
 integer::warm,runs,run,i,observation
 integer(int64)::t0,t1,rate,passes,count,last,total,p
 real(8)::seconds,elapsed
 logical::throughput,full
 character(64)::arg
 call get_command_argument(1,arg);read(arg,*)n
 call get_command_argument(2,arg);read(arg,*)lim
 call get_command_argument(3,arg);read(arg,*)warm
 call get_command_argument(4,arg);read(arg,*)runs
 call get_command_argument(5,arg);throughput=trim(arg)=='throughput'
 call get_command_argument(6,arg);read(arg,*)seconds
 call get_command_argument(8,arg);packed=trim(arg)=='packed'
 call get_command_argument(9,arg);full=trim(arg)=='1'
 call system_clock(count_rate=rate)
 do i=1,warm
  call make_sieve(flags)
  if(.not.throughput)call scan(flags,count,last)
  deallocate(flags)
 end do
 do run=1,runs
  passes=0;observation=0
  call system_clock(t0)
  do
   call make_sieve(next)
   if(throughput)observation=ieor(observation,int(next(modulo(passes,int(size(next),int64))+lbound(next,1))))
   call move_alloc(next,flags)
   passes=passes+1
   if(.not.throughput)call scan(flags,count,last)
   call system_clock(t1)
   elapsed=real(t1-t0,8)*1e9/real(rate,8)
   if(.not.throughput.or.elapsed>=seconds*1e9)exit
  end do
  if(throughput)call scan(flags,count,last)
  total=2;p=3
  do while(p<=last)
   if(.not.composite(flags,p/2))total=modulo(total+p,1000000007_int64)
   p=p+2
  end do
  write(*,'(A,I0,A,I0,A,I0,A,I0,A,I0,A,I0)',advance='no') &
   '{"elapsed_ns":',nint(elapsed,int64),',"passes":',passes,',"count":',count, &
   ',"last_prime":',last,',"checksum":',total,',"observation":',observation
  if(full)then
   write(*,'(A)',advance='no')',"primes":[2'
   p=3
   do while(p<=last)
    if(.not.composite(flags,p/2))write(*,'(A,I0)',advance='no')',',p
    p=p+2
   end do
   write(*,'(A)',advance='no')']'
  end if
  write(*,'(A)')'}'
  deallocate(flags)
 end do
end program
