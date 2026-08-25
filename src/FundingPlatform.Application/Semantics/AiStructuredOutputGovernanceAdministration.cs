using System.Globalization;

namespace FundingPlatform.Application.Semantics;

public sealed partial class AiProviderGovernanceAdministrationService
{
    public Task<AiStructuredOutputProviderPolicyMutation> RegisterStructuredOutputPolicyAsync(
        AiStructuredOutputProviderPolicyCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var nowUtc = timeProvider.GetUtcNow();
        var normalized = command with
        {
            Code = (command.Code ?? string.Empty).Trim().ToLowerInvariant(),
            EndpointOrigin = NormalizeOrigin(command.EndpointOrigin),
            DataResidencyCode = (command.DataResidencyCode ?? string.Empty)
                .Trim().ToLowerInvariant(),
            DpaReferenceHash = command.DpaReferenceHash?.ToArray() ?? [],
            TermsSnapshotHash = command.TermsSnapshotHash?.ToArray() ?? [],
            IdempotencyKey = (command.IdempotencyKey ?? string.Empty).Trim()
        };
        if (normalized.SuperAdminUserPublicId == Guid.Empty ||
            !CodePattern().IsMatch(normalized.Code) ||
            normalized.Version is < 1 or > 1_000_000 ||
            !RegionEndpoints.TryGetValue(normalized.DataResidencyCode, out var endpoint) ||
            normalized.EndpointOrigin != endpoint ||
            normalized.DpaReferenceHash.Length != 32 ||
            normalized.TermsSnapshotHash.Length != 32 ||
            normalized.InputTokenCostUsdPerMillion is < 0.000001m or > 1000m ||
            normalized.OutputTokenCostUsdPerMillion is < 0.000001m or > 1000m ||
            normalized.ApprovedAtUtc.Offset != TimeSpan.Zero ||
            normalized.ApprovedAtUtc > nowUtc ||
            normalized.ExpiresAtUtc.Offset != TimeSpan.Zero ||
            normalized.ExpiresAtUtc <= nowUtc ||
            normalized.ExpiresAtUtc > nowUtc.AddYears(2) ||
            !ValidIdempotencyKey(normalized.IdempotencyKey))
            throw new ArgumentException(
                "The governed OpenAI Structured Outputs policy is invalid or incomplete.");
        var material = Frame(
            "AiStructuredOutputProviderPolicy/v1",
            normalized.SuperAdminUserPublicId.ToString("D"),
            normalized.Code,
            normalized.Version.ToString(CultureInfo.InvariantCulture),
            "gpt-5.6-sol",
            normalized.EndpointOrigin,
            normalized.DataResidencyCode,
            Convert.ToHexString(normalized.DpaReferenceHash),
            Convert.ToHexString(normalized.TermsSnapshotHash),
            normalized.InputTokenCostUsdPerMillion.ToString("0.000000", CultureInfo.InvariantCulture),
            normalized.OutputTokenCostUsdPerMillion.ToString("0.000000", CultureInfo.InvariantCulture),
            normalized.ApprovedAtUtc.UtcDateTime.ToString("O", CultureInfo.InvariantCulture),
            normalized.ExpiresAtUtc.UtcDateTime.ToString("O", CultureInfo.InvariantCulture));
        return repository.RegisterStructuredOutputPolicyAsync(
            normalized,
            Hash(normalized.IdempotencyKey),
            Hash(material),
            nowUtc,
            cancellationToken);
    }

    public Task<OpenAiExplanationConfigurationMutation>
        PublishOpenAiExplanationConfigurationAsync(
            OpenAiExplanationConfigurationCommand command,
            CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var normalized = command with
        {
            Code = (command.Code ?? string.Empty).Trim().ToLowerInvariant(),
            IdempotencyKey = (command.IdempotencyKey ?? string.Empty).Trim()
        };
        if (normalized.SuperAdminUserPublicId == Guid.Empty ||
            normalized.ProviderPolicyPublicId == Guid.Empty ||
            !CodePattern().IsMatch(normalized.Code) ||
            normalized.Version is < 1 or > 1_000_000 ||
            normalized.MaximumOutputTokens is < 128 or > 1024 ||
            normalized.MaximumCostUsdPerResult is < 0.000001m or > 1m ||
            normalized.MonthlyBudgetUsd < normalized.MaximumCostUsdPerResult ||
            normalized.MonthlyBudgetUsd > 10_000m ||
            !ValidIdempotencyKey(normalized.IdempotencyKey))
            throw new ArgumentException(
                "The governed OpenAI explanation configuration is invalid or incomplete.");
        var material = Frame(
            "OpenAiExplanationConfiguration/v1",
            normalized.SuperAdminUserPublicId.ToString("D"),
            normalized.ProviderPolicyPublicId.ToString("D"),
            normalized.Code,
            normalized.Version.ToString(CultureInfo.InvariantCulture),
            normalized.MaximumOutputTokens.ToString(CultureInfo.InvariantCulture),
            normalized.MaximumCostUsdPerResult.ToString("0.000000", CultureInfo.InvariantCulture),
            normalized.MonthlyBudgetUsd.ToString("0.000000", CultureInfo.InvariantCulture));
        var nowUtc = timeProvider.GetUtcNow();
        return repository.PublishOpenAiExplanationConfigurationAsync(
            normalized,
            Hash(normalized.IdempotencyKey),
            Hash(material),
            nowUtc,
            cancellationToken);
    }
}
