using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Application.FundingOpportunities;

namespace FundingPlatform.Infrastructure.FundingSources;

/// <summary>
/// Applies the durable SQL policy immediately before each outbound request. The
/// returned lease also enforces a conservative per-process delay; SQL remains the
/// cross-instance source of truth and atomically reserves the global slot.
/// </summary>
public sealed class GovernedAcquisitionRequestGate(TimeProvider timeProvider)
{
    private readonly ConcurrentDictionary<int, LocalGate> gates = new();

    public async Task<GovernedAcquisitionPermit> AuthorizeAsync(
        IFundingSourceAcquisitionAuthorizer authorizer,
        GovernedAcquisitionContext context,
        Uri exactDestination,
        TimeSpan configuredMinimumDelay,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(authorizer);
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(exactDestination);
        Validate(context, exactDestination, configuredMinimumDelay);

        var requestedInterval = configuredMinimumDelay >
                                TimeSpan.FromSeconds(60d / context.RequestRateLimitPerMinute)
            ? configuredMinimumDelay
            : TimeSpan.FromSeconds(60d / context.RequestRateLimitPerMinute);
        var minimumIntervalMilliseconds = Math.Clamp(
            checked((int)Math.Ceiling(requestedInterval.TotalMilliseconds)), 100, 60_000);
        var localGate = gates.GetOrAdd(context.FundingSourceId, static _ => new LocalGate());
        var localLease = await localGate.EnterAsync(
            requestedInterval,
            timeProvider,
            cancellationToken);
        try
        {
            // Reserve the cross-instance slot only after entering the per-process
            // gate. Otherwise a request waiting locally could use an already stale
            // durable reservation and bunch with a later instance.
            var nowUtc = timeProvider.GetUtcNow();
            var authorization = await authorizer.AuthorizeAsync(
                context.FundingSourceId,
                exactDestination,
                SHA256.HashData(Encoding.UTF8.GetBytes(exactDestination.AbsoluteUri)),
                context.AcquisitionPolicyFingerprint,
                minimumIntervalMilliseconds,
                nowUtc,
                cancellationToken);
            if (!authorization.Allowed ||
                !string.Equals(authorization.Code, "reserved", StringComparison.Ordinal) ||
                authorization.ReservedAtUtc is null ||
                authorization.RequestRateLimitPerMinute is not (>= 1 and <= 600) ||
                authorization.MaximumResponseBytes is not (>= 4_096 and <= 26_214_400) ||
                authorization.ContentRetentionDays is not (>= 1 and <= 3_650) ||
                authorization.AcquisitionPolicyVersion is null or < 1 ||
                authorization.AcquisitionPolicyFingerprint is not { Length: 32 })
            {
                throw new FundingSourceImportException(
                    "The funding source acquisition policy denied the outbound request.");
            }

            if (authorization.AcquisitionPolicyVersion != context.AcquisitionPolicyVersion ||
                !CryptographicOperations.FixedTimeEquals(
                    authorization.AcquisitionPolicyFingerprint,
                    context.AcquisitionPolicyFingerprint))
            {
                throw new FundingSourceImportException(
                    "The funding source acquisition policy changed before the outbound request.");
            }

            var reservedAtUtc = authorization.ReservedAtUtc.Value;
            if (reservedAtUtc < nowUtc.Subtract(TimeSpan.FromMinutes(1)) ||
                reservedAtUtc > nowUtc.AddHours(1))
            {
                throw new FundingSourceImportException(
                    "The funding source acquisition reservation was invalid.");
            }

            var reservationDelay = reservedAtUtc - timeProvider.GetUtcNow();
            if (reservationDelay > TimeSpan.Zero)
            {
                await Task.Delay(reservationDelay, timeProvider, cancellationToken);
            }

            return new GovernedAcquisitionPermit(
                Math.Min(context.MaximumResponseBytes, authorization.MaximumResponseBytes.Value),
                Math.Min(context.ContentRetentionDays, authorization.ContentRetentionDays.Value),
                authorization.AcquisitionPolicyVersion.Value,
                localLease);
        }
        catch
        {
            localLease.Dispose();
            throw;
        }
    }

    private static void Validate(
        GovernedAcquisitionContext context,
        Uri destination,
        TimeSpan configuredMinimumDelay)
    {
        if (context.FundingSourceId < 1 ||
            context.RequestRateLimitPerMinute is < 1 or > 600 ||
            context.MaximumResponseBytes is < 4_096 or > 26_214_400 ||
            context.ContentRetentionDays is < 1 or > 3_650 ||
            context.AcquisitionPolicyVersion < 1 ||
            context.AcquisitionPolicyFingerprint is not { Length: 32 })
        {
            throw new FundingSourceImportException(
                "The durable funding source acquisition context was invalid.");
        }

        if (!destination.IsAbsoluteUri || destination.Scheme != Uri.UriSchemeHttps ||
            destination.Port != 443 || !string.IsNullOrEmpty(destination.UserInfo) ||
            !string.IsNullOrEmpty(destination.Fragment) ||
            destination.AbsoluteUri.Length > 2_048 || HasControl(destination.AbsoluteUri) ||
            Uri.CheckHostName(destination.Host) != UriHostNameType.Dns ||
            configuredMinimumDelay < TimeSpan.Zero ||
            configuredMinimumDelay > TimeSpan.FromMinutes(1))
        {
            throw new FundingSourceImportException(
                "The outbound funding source destination was rejected.");
        }
    }

    private static bool HasControl(string value) =>
        value.Contains('\r') || value.Contains('\n') || value.Contains('\0');

    private sealed class LocalGate
    {
        private readonly SemaphoreSlim semaphore = new(1, 1);
        private DateTimeOffset lastRequestAtUtc = DateTimeOffset.MinValue;

        public async Task<IDisposable> EnterAsync(
            TimeSpan minimumDelay,
            TimeProvider clock,
            CancellationToken cancellationToken)
        {
            await semaphore.WaitAsync(cancellationToken);
            try
            {
                var delay = lastRequestAtUtc.Add(minimumDelay) - clock.GetUtcNow();
                if (delay > TimeSpan.Zero)
                {
                    await Task.Delay(delay, clock, cancellationToken);
                }

                lastRequestAtUtc = clock.GetUtcNow();
                return new Releaser(semaphore);
            }
            catch
            {
                semaphore.Release();
                throw;
            }
        }
    }

    private sealed class Releaser(SemaphoreSlim semaphore) : IDisposable
    {
        private int disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0)
            {
                semaphore.Release();
            }
        }
    }
}

public sealed class GovernedAcquisitionPermit(
    int maximumResponseBytes,
    short contentRetentionDays,
    int acquisitionPolicyVersion,
    IDisposable localLease) : IDisposable
{
    private IDisposable? localLease = localLease;

    public int MaximumResponseBytes { get; } = maximumResponseBytes;
    public short ContentRetentionDays { get; } = contentRetentionDays;
    public int AcquisitionPolicyVersion { get; } = acquisitionPolicyVersion;

    public void Dispose() => Interlocked.Exchange(ref localLease, null)?.Dispose();
}
