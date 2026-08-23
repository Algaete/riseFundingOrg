using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public interface IFundingSourceProvider
{
    FundingSourceDescriptor Source { get; }

    Task<IReadOnlyList<FundingSourceObservation>> FetchOpenAsync(
        string keyword,
        int maximumResults,
        GovernedAcquisitionContext governance,
        CancellationToken cancellationToken);
}

public sealed record GovernedAcquisitionContext(
    int FundingSourceId,
    int RequestRateLimitPerMinute,
    int MaximumResponseBytes,
    short ContentRetentionDays,
    int AcquisitionPolicyVersion,
    byte[] AcquisitionPolicyFingerprint);

public sealed record FundingSourceAcquisitionAuthorization(
    bool Allowed,
    string Code,
    DateTimeOffset? ReservedAtUtc,
    DateTimeOffset? NextAllowedAtUtc,
    int? RetryAfterMilliseconds,
    int? RequestRateLimitPerMinute,
    int? MaximumResponseBytes,
    short? ContentRetentionDays,
    int? AcquisitionPolicyVersion,
    byte[]? AcquisitionPolicyFingerprint);

public interface IFundingSourceAcquisitionAuthorizer
{
    Task<FundingSourceAcquisitionAuthorization> AuthorizeAsync(
        int fundingSourceId,
        Uri exactDestination,
        byte[] canonicalDestinationHash,
        byte[] acquisitionPolicyFingerprint,
        int minimumIntervalMilliseconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public interface IFundingSourceProviderRegistry
{
    bool TryGet(string providerCode, out IFundingSourceProvider provider);
}

public sealed class FundingSourceProviderRegistry : IFundingSourceProviderRegistry
{
    private readonly IReadOnlyDictionary<string, IFundingSourceProvider> providers;

    public FundingSourceProviderRegistry(
        IEnumerable<IFundingSourceProvider> providers,
        IEnumerable<string> allowedProviderCodes)
    {
        ArgumentNullException.ThrowIfNull(providers);
        ArgumentNullException.ThrowIfNull(allowedProviderCodes);

        var allowlist = allowedProviderCodes
            .Select(code => code?.Trim() ?? string.Empty)
            .Where(code => code.Length > 0)
            .ToHashSet(StringComparer.Ordinal);
        if (allowlist.Count == 0)
        {
            throw new InvalidOperationException("At least one funding provider must be allowlisted.");
        }

        var registered = new Dictionary<string, IFundingSourceProvider>(StringComparer.Ordinal);
        foreach (var provider in providers)
        {
            ArgumentNullException.ThrowIfNull(provider);
            var code = provider.Source.ProviderCode;
            ArgumentException.ThrowIfNullOrWhiteSpace(code);
            if (!allowlist.Contains(code))
            {
                continue;
            }

            if (!registered.TryAdd(code, provider))
            {
                throw new InvalidOperationException($"Funding provider code '{code}' is duplicated.");
            }
        }

        if (!allowlist.SetEquals(registered.Keys))
        {
            throw new InvalidOperationException("Every allowlisted funding provider must be registered.");
        }

        this.providers = registered;
    }

    public bool TryGet(string providerCode, out IFundingSourceProvider provider)
    {
        if (string.IsNullOrWhiteSpace(providerCode))
        {
            provider = null!;
            return false;
        }

        return providers.TryGetValue(providerCode, out provider!);
    }
}

public sealed record FundingSourceDescriptor(
    string ProviderCode,
    string Name,
    byte ProviderType,
    string? BaseUrl,
    string? TermsUrl,
    string? ScheduleCron,
    int MinimumDelaySeconds,
    string UserAgent);
