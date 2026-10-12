# Prime-calculation kernel. Allocation, timing, repetition and verification are supplied
# by the C harness.
# PRIME-BEGIN: Kernel inputs
# The caller supplies zero-filled flags, the search limit, and the requested count. The
# kernel returns the final prime, or zero on failure.
# Windows x64: rcx=flags, rdx=limit, r8=count; rax=return value.
.text
.globl sieve_kernel
sieve_kernel:
    pushq %rdi
    pushq %rsi
    movq %rcx, %rdi
    movq %rdx, %rsi
    movq %r8, %rdx
    movq $3, %rcx
    movq %rsi, %r9
    shrq $1, %r9
# PRIME-END
# PRIME-BEGIN: Mark composites
# Try odd divisors through the square root of the limit. Start at p squared; an index
# step of p skips even multiples.
L_outer:
    movq %rcx, %rax
    imulq %rcx, %rax
    cmpq %rsi, %rax
    ja L_scan_setup
    movq %rcx, %r8
    shrq $1, %r8
    cmpb $0, (%rdi,%r8)
    jne L_next_p
    movq %rax, %r8
    shrq $1, %r8
L_mark:
    movb $1, (%rdi,%r8)
    addq %rcx, %r8
    cmpq %r9, %r8
    jbe L_mark
L_next_p:
    addq $2, %rcx
    jmp L_outer
# PRIME-END
# PRIME-BEGIN: Find the Nth prime
# Count 2 as the first prime, then scan odd candidates. Stop when the requested number
# of primes has been found.
L_scan_setup:
    cmpq $1, %rdx
    je L_two
    movq $3, %rcx
    movq $1, %r10
L_scan:
    cmpq %rsi, %rcx
    ja L_failure
    movq %rcx, %r8
    shrq $1, %r8
    cmpb $0, (%rdi,%r8)
    jne L_next_scan
    incq %r10
    cmpq %rdx, %r10
    je L_done
L_next_scan:
    addq $2, %rcx
    jmp L_scan
L_done:
    movq %rcx, %rax
    popq %rsi
    popq %rdi
    ret
L_two:
    movq $2, %rax
    popq %rsi
    popq %rdi
    ret
L_failure:
    xorq %rax, %rax
    popq %rsi
    popq %rdi
    ret
# PRIME-END
