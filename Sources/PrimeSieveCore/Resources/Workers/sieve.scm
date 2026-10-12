;; Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
;; The harness repeats warm-up and measured runs; only allocation, marking and scanning
;; are timed.
;; After timing, a modular checksum verifies the result and JSON reports each measured run.
(use-modules (srfi srfi-4) (ice-9 format))
(define args (map string->number (cdr (command-line))))
(define n (list-ref args 0))(define lim (list-ref args 1))(define warm (list-ref args 2))(define runs (list-ref args 3))
(do ((run (- warm) (+ run 1))) ((>= run runs))
 (let* ((start (get-internal-real-time))
        ;; PRIME-BEGIN: Allocate candidates
        ;; Create zero-filled candidate storage. Each slot represents an odd number; zero
        ;; means not yet marked composite.
        (flags (make-u8vector (+ (quotient lim 2) 1) 0)))
        ;; PRIME-END
  ;; PRIME-BEGIN: Mark composites
  ;; Try odd divisors through the square root of the limit. Start at p squared; an index
  ;; step of p skips even multiples.
  (let sieve ((p 3))
   (when (<= p (quotient lim p))
    (when (zero? (u8vector-ref flags (quotient p 2)))
     (do ((j (quotient (* p p) 2) (+ j p))) ((> j (quotient lim 2))) (u8vector-set! flags j 1)))
    (sieve (+ p 2))))
  ;; PRIME-END
  ;; PRIME-BEGIN: Find the Nth prime
  ;; Count 2 as the first prime, then scan odd candidates. Stop when the requested number
  ;; of primes has been found.
  (let* ((result (let scan ((p 3) (count 1) (last 2))
          (cond ((or (>= count n) (> p lim)) (cons count last))
           ((zero? (u8vector-ref flags (quotient p 2))) (scan (+ p 2) (+ count 1) p))
           (else (scan (+ p 2) count last)))))
  ;; PRIME-END
         (ns (inexact->exact (round (* (- (get-internal-real-time) start) (/ 1000000000 internal-time-units-per-second)))))
         (last (cdr result))
         (sum (let loop ((p 3) (total 2)) (if (> p last) total
                (loop (+ p 2) (if (zero? (u8vector-ref flags (quotient p 2))) (modulo (+ total p) 1000000007) total))))))
   (when (>= run 0) (format #t "{\"elapsed_ns\":~a,\"count\":~a,\"last_prime\":~a,\"checksum\":~a}~%" ns (car result) last sum)))))
