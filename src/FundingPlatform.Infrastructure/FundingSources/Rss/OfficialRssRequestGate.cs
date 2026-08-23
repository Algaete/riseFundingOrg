namespace FundingPlatform.Infrastructure.FundingSources.Rss;

public sealed class OfficialRssRequestGate(TimeProvider timeProvider)
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private DateTimeOffset lastRequestAtUtc = DateTimeOffset.MinValue;

    public async Task<IDisposable> EnterAsync(
        TimeSpan minimumDelay,
        CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            var delay = lastRequestAtUtc.Add(minimumDelay) - timeProvider.GetUtcNow();
            if (delay > TimeSpan.Zero)
                await Task.Delay(delay, timeProvider, cancellationToken);
            lastRequestAtUtc = timeProvider.GetUtcNow();
            return new Releaser(gate);
        }
        catch
        {
            gate.Release();
            throw;
        }
    }

    private sealed class Releaser(SemaphoreSlim gate) : IDisposable
    {
        private int disposed;
        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0) gate.Release();
        }
    }
}
