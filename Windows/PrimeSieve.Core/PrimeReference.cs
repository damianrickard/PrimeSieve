namespace PrimeSieve.Core;

public static class PrimeReference
{
    public static PrimeSignature Calculate(BenchmarkConfiguration config, CancellationToken token = default) =>
        Calculate(config.Workload == Workload.FirstN ? config.PrimeCount : int.MaxValue, config.SieveLimit, token);
    public static int[] Sequence(int count, int limit)
    {
        var primes = new List<int>();
        for (var candidate = 2; candidate <= limit; candidate++)
            if (primes.TakeWhile(p => p <= candidate / p).All(p => candidate % p != 0))
            { primes.Add(candidate); if (primes.Count == count) break; }
        return primes.ToArray();
    }
    // Deliberately independent from the workers: full-number, rather than odd-only, storage.
    public static PrimeSignature Calculate(int count, int limit, CancellationToken cancellationToken = default)
    {
        if (count < 1 || limit is < 2 or > 200_000_000) throw new ArgumentException("Invalid reference workload.");
        var composite = new bool[limit + 1];
        for (var p = 2; p <= limit / p; p++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (composite[p]) continue;
            for (var multiple = p * p; multiple <= limit; multiple += p)
            {
                if ((multiple & 8191) == 0) cancellationToken.ThrowIfCancellationRequested();
                composite[multiple] = true;
            }
        }
        int found = 0, last = 0;
        long checksum = 0;
        for (var candidate = 2; candidate <= limit; candidate++)
        {
            if ((candidate & 8191) == 0) cancellationToken.ThrowIfCancellationRequested();
            if (composite[candidate]) continue;
            last = candidate;
            checksum = (checksum + candidate) % 1_000_000_007;
            if (++found == count) return new(found, candidate, checksum);
        }
        if (count == int.MaxValue) return new(found, last, checksum);
        throw new InvalidDataException("The common search bound did not contain enough primes.");
    }
}
