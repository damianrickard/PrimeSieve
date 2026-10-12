#lang racket/base
;; Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
;; The harness repeats warm-up and measured runs; only allocation, marking and scanning
;; are timed.
;; After timing, a modular checksum verifies the result and JSON reports each measured run.
(require racket/format)
(define args (map string->number (vector->list (current-command-line-arguments))))
(define n (list-ref args 0))(define lim (list-ref args 1))(define warm (list-ref args 2))(define runs (list-ref args 3))
(for ([run (in-range (- warm) runs)])
 (define start (current-inexact-monotonic-milliseconds))
 ;; PRIME-BEGIN: Allocate candidates
 ;; Create zero-filled candidate storage. Each slot represents an odd number; zero means
 ;; not yet marked composite.
 (define flags (make-bytes (+ (quotient lim 2) 1) 0))
 ;; PRIME-END
 ;; PRIME-BEGIN: Mark composites
 ;; Try odd divisors through the square root of the limit. Start at p squared; an index
 ;; step of p skips even multiples.
 (let sieve ([p 3])
  (when (<= p (quotient lim p))
   (when (zero? (bytes-ref flags (quotient p 2)))
    (for ([j (in-range (quotient (* p p) 2) (+ (quotient lim 2) 1) p)]) (bytes-set! flags j 1)))
   (sieve (+ p 2))))
 ;; PRIME-END
 ;; PRIME-BEGIN: Find the Nth prime
 ;; Count 2 as the first prime, then scan odd candidates. Stop when the requested number
 ;; of primes has been found.
 (define-values (count last)
  (let scan ([p 3] [count 1] [last 2])
   (cond [(or (>= count n) (> p lim)) (values count last)]
    [(zero? (bytes-ref flags (quotient p 2))) (scan (+ p 2) (+ count 1) p)]
    [else (scan (+ p 2) count last)])))
 ;; PRIME-END
 (define ns (* (- (current-inexact-monotonic-milliseconds) start) 1000000))
 (define sum (for/fold ([total 2]) ([p (in-range 3 (+ last 1) 2)] #:when (zero? (bytes-ref flags (quotient p 2)))) (modulo (+ total p) 1000000007)))
 (when (>= run 0) (printf "{\"elapsed_ns\":~a,\"count\":~a,\"last_prime\":~a,\"checksum\":~a}\n" (~r ns #:precision 0) count last sum)))
