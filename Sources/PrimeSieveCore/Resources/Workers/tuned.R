# Protocol 3: bulk raw-vector implementation. No external sieve dependencies.
a <- commandArgs(trailingOnly=TRUE)
n <- as.integer(a[1]); limit <- as.integer(a[2]); warm <- as.integer(a[3]); runs <- as.integer(a[4])
throughput <- a[5] == "throughput"; duration <- as.numeric(a[6]) * 1e9; full <- a[9] == "1"
dyn.load(if (.Platform$OS.type == "windows") "clock.dll" else "clock.dylib")
now <- function() .C("primesieve_clock", out=double(1))$out
# PRIME-BEGIN: Allocate and mark composites
# Raw bytes avoid the larger logical-vector representation. Subassignment marks a
# whole progression of multiples using R's built-in vector operations.
sieve <- function() {
    flags <- raw(limit %/% 2L + 1L)
    flags[1L] <- as.raw(1)
    bound <- as.integer(floor(sqrt(limit)))
    if (bound >= 3L) for (p in seq.int(3L, bound, 2L)) {
        if (flags[p %/% 2L + 1L] == as.raw(0)) {
            start <- (p*p) %/% 2L + 1L
            flags[seq.int(start, length(flags), p)] <- as.raw(1)
        }
    }
    flags
}
# PRIME-END
# PRIME-BEGIN: Find the requested primes
scan <- function(flags) {
    candidates <- (which(flags == as.raw(0)) - 1L) * 2L + 1L
    candidates <- candidates[candidates <= limit]
    head(c(2L, candidates), n)
}
# PRIME-END
if (warm > 0L) for (i in seq_len(warm)) { flags <- sieve(); if (!throughput) scan(flags) }
flags <- NULL
for (i in seq_len(runs)) {
    passes <- 0; observation <- 0L
    start <- now()
    repeat {
        flags <- sieve()
        if (throughput) observation <- bitwXor(observation, as.integer(flags[passes %% length(flags) + 1]))
        passes <- passes + 1
        if (!throughput) primes <- scan(flags)
        elapsed <- now() - start
        if (!throughput || elapsed >= duration) break
    }
    if (throughput) primes <- scan(flags)
    checksum <- sum(as.double(primes)) %% 1000000007
    cat(sprintf('{"elapsed_ns":%.0f,"passes":%.0f,"count":%d,"last_prime":%d,"checksum":%.0f,"observation":%d',
                elapsed, passes, length(primes), tail(primes, 1), checksum, observation))
    if (full) cat(',"primes":[', paste(primes, collapse=","), ']', sep="")
    cat("}\n"); flush.console()
    flags <- NULL
}
