;; Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
;; The harness repeats warm-up and measured runs; only allocation, marking and scanning
;; are timed. A modular checksum verifies the result after timing.
(set! *warn-on-reflection* true)
(set! *unchecked-math* :warn-on-boxed)
(let [args (vec (map #(Long/parseLong %) *command-line-args*))
      n (long (nth args 0))
      limit (long (nth args 1))
      warm (long (nth args 2))
      runs (long (nth args 3))]
  (loop [run (- warm)]
    (when (< run runs)
      (let [start (System/nanoTime)
            ;; PRIME-BEGIN: Allocate candidates
            ;; Each zero-filled byte represents an odd candidate. Primitive long bounds
            ;; and a typed byte array avoid boxing and reflective access in the hot loops.
            half (quot limit 2)
            ^bytes flags (byte-array (inc half))]
            ;; PRIME-END
        ;; PRIME-BEGIN: Mark composites
        ;; Try odd divisors through the square root. Starting at p squared avoids
        ;; already marked smaller multiples; an index step of p skips even multiples.
        (loop [p (long 3)]
          (when (<= p (quot limit p))
            (when (zero? (aget flags (int (quot p 2))))
              (loop [j (quot (* p p) 2)]
                (when (<= j half)
                  (aset flags (int j) (byte 1))
                  (recur (+ j p)))))
            (recur (+ p 2))))
        ;; PRIME-END
        ;; PRIME-BEGIN: Find the Nth prime
        ;; Count 2 first, then scan the remaining odd candidates until N primes are found.
        (let [result (loop [p (long 3) count (long 1) last (long 2)]
                       (if (or (>= count n) (> p limit))
                         [count last]
                         (if (zero? (aget flags (int (quot p 2))))
                           (recur (+ p 2) (inc count) p)
                           (recur (+ p 2) count last))))
        ;; PRIME-END
              ns (- (System/nanoTime) start)
              count (long (nth result 0))
              last (long (nth result 1))
              sum (loop [p (long 3) sum (long 2)]
                    (if (> p last) sum
                      (recur (+ p 2)
                             (if (zero? (aget flags (int (quot p 2))))
                               (long (mod (+ sum p) 1000000007)) sum))))]
          (when (>= run 0)
            (println (str "{\"elapsed_ns\":" ns ",\"count\":" count
                          ",\"last_prime\":" last ",\"checksum\":" sum "}")))))
      (recur (inc run)))))
(shutdown-agents)
