// Prime-calculation kernel. Allocation, timing, repetition and verification are supplied
// by the C harness.
// PRIME-BEGIN: Kernel inputs
// The caller supplies zero-filled flags, the search limit, and the requested count. The
// kernel returns the final prime, or zero on failure. ARM64: x0=flags, x1=limit,
// x2=count; x0=return value.
.text
.p2align 2
.globl _sieve_kernel
_sieve_kernel:
    mov x3, #3
    lsr x6, x1, #1
// PRIME-END
// PRIME-BEGIN: Mark composites
// Try odd divisors through the square root of the limit. Start at p squared; an index
// step of p skips even multiples.
L_outer:
    mul x4, x3, x3
    cmp x4, x1
    b.hi L_scan_setup
    lsr x5, x3, #1
    ldrb w7, [x0, x5]
    cbnz w7, L_next_p
    lsr x5, x4, #1
    mov w7, #1
L_mark:
    strb w7, [x0, x5]
    add x5, x5, x3
    cmp x5, x6
    b.ls L_mark
L_next_p:
    add x3, x3, #2
    b L_outer
// PRIME-END
// PRIME-BEGIN: Find the Nth prime
// Count 2 as the first prime, then scan odd candidates. Stop when the requested number
// of primes has been found.
L_scan_setup:
    cmp x2, #1
    b.eq L_two
    mov x3, #3
    mov x4, #1
L_scan:
    cmp x3, x1
    b.hi L_failure
    lsr x5, x3, #1
    ldrb w7, [x0, x5]
    cbnz w7, L_next_scan
    add x4, x4, #1
    cmp x4, x2
    b.eq L_done
L_next_scan:
    add x3, x3, #2
    b L_scan
L_done:
    mov x0, x3
    ret
L_two:
    mov x0, #2
    ret
L_failure:
    mov x0, #0
    ret
// PRIME-END
