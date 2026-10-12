;; Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
;; The harness repeats warm-up and measured runs; only allocation, marking and scanning
;; are timed.
;; After timing, a modular checksum verifies the result and JSON reports each measured run.
(declaim (optimize (speed 3) (safety 1)))
(sb-alien:load-shared-object "./clock.dylib")
(sb-alien:define-alien-routine ("primesieve_now" now-ns) sb-alien:double)
(defun benchmark (n limit warm runs)
 (declare (type fixnum n limit warm runs))
 (loop for run from (- warm) below runs do
  (let* ((start (now-ns))
         ;; PRIME-BEGIN: Allocate candidates
         ;; Create zero-filled candidate storage. Each slot represents an odd number;
         ;; zero means not yet marked composite.
         (flags (make-array (1+ (floor limit 2)) :element-type '(unsigned-byte 8) :initial-element 0)) (count 1) (last 2))
   (declare (type fixnum count last))
         ;; PRIME-END
   ;; PRIME-BEGIN: Mark composites
   ;; Try odd divisors through the square root of the limit. Start at p squared; an index
   ;; step of p skips even multiples.
   (loop for p of-type fixnum from 3 by 2 while (<= p (floor limit p)) do
    (when (zerop (aref flags (floor p 2)))
     (loop for j of-type fixnum from (floor (* p p) 2) to (floor limit 2) by p do (setf (aref flags j) 1))))
   ;; PRIME-END
   ;; PRIME-BEGIN: Find the Nth prime
   ;; Count 2 as the first prime, then scan odd candidates. Stop when the requested
   ;; number of primes has been found.
   (loop for p of-type fixnum from 3 to limit by 2 while (< count n) do
    (when (zerop (aref flags (floor p 2))) (incf count) (setf last p)))
   ;; PRIME-END
   (let ((elapsed (- (now-ns) start)) (sum 2))
    (loop for p of-type fixnum from 3 to last by 2 do (when (zerop (aref flags (floor p 2))) (setf sum (mod (+ sum p) 1000000007))))
    (when (>= run 0) (format t "{~s:~d,~s:~d,~s:~d,~s:~d}~%" "elapsed_ns" (round elapsed) "count" count "last_prime" last "checksum" sum))))))
(apply #'benchmark (mapcar #'parse-integer (cdr sb-ext:*posix-argv*)))
