{-# LANGUAGE BangPatterns, FlexibleContexts #-}
-- Odd-only Sieve of Eratosthenes. Inputs: n (prime count) and limit (shared search bound).
-- The harness repeats warm-up and measured runs; only allocation, marking and scanning
-- are timed.
-- After timing, a modular checksum verifies the result and JSON reports each measured run.
import Data.Array.IO
import Data.Word
import GHC.Clock
import System.Environment
import Control.Monad
import Text.Printf
main = do
  [n,lim,warm,runs] <- map read <$> getArgs :: IO [Int]
  forM_ [-warm..runs-1] $ \run -> do
    start <- getMonotonicTimeNSec
    -- PRIME-BEGIN: Allocate candidates
    -- Create zero-filled candidate storage. Each slot represents an odd number; zero
    -- means not yet marked composite.
    flags <- newArray (0,lim `div` 2) 0 :: IO (IOUArray Int Word8)
    -- PRIME-END
    -- PRIME-BEGIN: Mark composites
    -- Try odd divisors through the square root of the limit. Start at p squared; an
    -- index step of p skips even multiples.
    let mark !j !p = when (j<=lim `div` 2) $ writeArray flags j 1 >> mark (j+p) p
        sieve !p = when (p<=lim `div` p) $ do
          v <- readArray flags (p `div` 2)
          when (v==0) $ mark (p*p `div` 2) p
          sieve (p+2)
    -- PRIME-END
        -- PRIME-BEGIN: Find the Nth prime
        -- Count 2 as the first prime, then scan odd candidates. Stop when the requested
        -- number of primes has been found.
        scan !p !count !lastP | count>=n || p>lim = pure (count,lastP)
        scan !p !count !lastP = do
          v <- readArray flags (p `div` 2)
          if v==0 then scan (p+2) (count+1) p else scan (p+2) count lastP
        -- PRIME-END
        checksum !p !lastP !total | p>lastP = pure total
        checksum !p !lastP !total = do
          v <- readArray flags (p `div` 2)
          checksum (p+2) lastP (if v==0 then (total+p) `mod` 1000000007 else total)
    -- PRIME-BEGIN: Run the calculation
    -- Allocate candidates, mark composites, and scan for the requested final prime using
    -- the helpers shown here.
    sieve 3
    (count,lastP) <- scan 3 1 2
    -- PRIME-END
    end <- getMonotonicTimeNSec
    total <- checksum 3 lastP 2
    when (run>=0) $ printf "{\"elapsed_ns\":%d,\"count\":%d,\"last_prime\":%d,\"checksum\":%d}\n" (end-start) count lastP total
