using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace FundingPlatform.Application.Semantics;

public sealed record AiEmbeddingProviderPolicyCommand(
    Guid SuperAdminUserPublicId,
    string Code,
    int Version,
    string ModelCode,
    string EndpointOrigin,
    string DataResidencyCode,
    byte[] DpaReferenceHash,
    byte[] TermsSnapshotHash,
    decimal InputTokenCostUsdPerMillion,
    DateTimeOffset ApprovedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    string IdempotencyKey);

public sealed record AiEmbeddingProviderPolicyMutation(
    bool Succeeded,
    string Code,
    bool WasReplay,
    Guid PolicyPublicId,
    string PolicyVersion,
    string ProviderCode,
    string ModelCode,
    string EndpointOrigin,
    byte RetentionMode,
    short MaximumProviderRetentionDays,
    string DataResidencyCode,
    byte[] PolicyFingerprint,
    decimal InputTokenCostUsdPerMillion,
    bool ExternalProcessingAllowed,
    bool IsActive,
    DateTimeOffset ApprovedAtUtc,
    DateTimeOffset ExpiresAtUtc);

public sealed record OpenAiSemanticConfigurationCommand(
    Guid SuperAdminUserPublicId,
    Guid ProviderPolicyPublicId,
    string Code,
    int Version,
    byte MaximumBatchSize,
    decimal MaximumCostUsdPerEmbedding,
    decimal MonthlyBudgetUsd,
    string IdempotencyKey);

public sealed record OpenAiSemanticConfigurationMutation(
    bool Succeeded,
    string Code,
    bool WasReplay,
    Guid ConfigurationPublicId,
    string ConfigurationVersion,
    Guid ProviderPolicyPublicId,
    byte[] ProviderPolicyFingerprint,
    string ProviderCode,
    string ModelCode,
    short Dimensions,
    byte MaximumBatchSize,
    decimal MaximumCostUsdPerEmbedding,
    decimal MonthlyBudgetUsd,
    bool IsActive,
    DateTimeOffset PublishedAtUtc);

public sealed record AiStructuredOutputProviderPolicyCommand(
    Guid SuperAdminUserPublicId,
    string Code,
    int Version,
    string EndpointOrigin,
    string DataResidencyCode,
    byte[] DpaReferenceHash,
    byte[] TermsSnapshotHash,
    decimal InputTokenCostUsdPerMillion,
    decimal OutputTokenCostUsdPerMillion,
    DateTimeOffset ApprovedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    string IdempotencyKey);

public sealed record AiStructuredOutputProviderPolicyMutation(
    bool Succeeded,
    string Code,
    bool WasReplay,
    Guid PolicyPublicId,
    string PolicyVersion,
    string ProviderCode,
    string ModelCode,
    byte Capability,
    string EndpointOrigin,
    byte RetentionMode,
    short MaximumProviderRetentionDays,
    string DataResidencyCode,
    byte[] PolicyFingerprint,
    decimal InputTokenCostUsdPerMillion,
    decimal OutputTokenCostUsdPerMillion,
    bool ExternalProcessingAllowed,
    bool IsActive,
    DateTimeOffset ApprovedAtUtc,
    DateTimeOffset ExpiresAtUtc);

public sealed record OpenAiExplanationConfigurationCommand(
    Guid SuperAdminUserPublicId,
    Guid ProviderPolicyPublicId,
    string Code,
    int Version,
    short MaximumOutputTokens,
    decimal MaximumCostUsdPerResult,
    decimal MonthlyBudgetUsd,
    string IdempotencyKey);

public sealed record OpenAiExplanationConfigurationMutation(
    bool Succeeded,
    string Code,
    bool WasReplay,
    Guid ConfigurationPublicId,
    string ConfigurationVersion,
    Guid ProviderPolicyPublicId,
    byte[] ProviderPolicyFingerprint,
    string ProviderCode,
    string ModelCode,
    string InputSchemaVersion,
    string OutputSchemaVersion,
    string PromptVersion,
    byte[] PromptFingerprint,
    byte[] ResponseSchemaFingerprint,
    short MaximumOutputTokens,
    decimal MaximumCostUsdPerResult,
    decimal MonthlyBudgetUsd,
    bool IsActive,
    DateTimeOffset PublishedAtUtc);

public interface IAiProviderGovernanceAdministrationRepository
{
    Task<AiEmbeddingProviderPolicyMutation> RegisterEmbeddingPolicyAsync(
        AiEmbeddingProviderPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<OpenAiSemanticConfigurationMutation> PublishOpenAiConfigurationAsync(
        OpenAiSemanticConfigurationCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<AiStructuredOutputProviderPolicyMutation> RegisterStructuredOutputPolicyAsync(
        AiStructuredOutputProviderPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<OpenAiExplanationConfigurationMutation> PublishOpenAiExplanationConfigurationAsync(
        OpenAiExplanationConfigurationCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);
}

public sealed partial class AiProviderGovernanceAdministrationService(
    IAiProviderGovernanceAdministrationRepository repository,
    TimeProvider timeProvider)
{
    private static readonly IReadOnlyDictionary<string, string> RegionEndpoints =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["global"] = "https://api.openai.com",
            ["us"] = "https://us.api.openai.com",
            ["eu"] = "https://eu.api.openai.com",
            ["au"] = "https://au.api.openai.com",
            ["ca"] = "https://ca.api.openai.com",
            ["jp"] = "https://jp.api.openai.com",
            ["in"] = "https://in.api.openai.com",
            ["sg"] = "https://sg.api.openai.com",
            ["kr"] = "https://kr.api.openai.com",
            ["gb"] = "https://gb.api.openai.com",
            ["ae"] = "https://ae.api.openai.com"
        };

    public Task<AiEmbeddingProviderPolicyMutation> RegisterEmbeddingPolicyAsync(
        AiEmbeddingProviderPolicyCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var nowUtc = timeProvider.GetUtcNow();
        var normalized = command with
        {
            Code = (command.Code ?? string.Empty).Trim().ToLowerInvariant(),
            ModelCode = (command.ModelCode ?? string.Empty).Trim(),
            EndpointOrigin = NormalizeOrigin(command.EndpointOrigin),
            DataResidencyCode = (command.DataResidencyCode ?? string.Empty)
                .Trim().ToLowerInvariant(),
            DpaReferenceHash = command.DpaReferenceHash?.ToArray() ?? [],
            TermsSnapshotHash = command.TermsSnapshotHash?.ToArray() ?? [],
            IdempotencyKey = (command.IdempotencyKey ?? string.Empty).Trim()
        };
        ValidatePolicy(normalized, nowUtc);
        return repository.RegisterEmbeddingPolicyAsync(
            normalized,
            Hash(normalized.IdempotencyKey),
            Hash(PolicyMaterial(normalized)),
            nowUtc,
            cancellationToken);
    }

    public Task<OpenAiSemanticConfigurationMutation> PublishOpenAiConfigurationAsync(
        OpenAiSemanticConfigurationCommand command,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        var normalized = command with
        {
            Code = (command.Code ?? string.Empty).Trim().ToLowerInvariant(),
            IdempotencyKey = (command.IdempotencyKey ?? string.Empty).Trim()
        };
        ValidateConfiguration(normalized);
        var nowUtc = timeProvider.GetUtcNow();
        return repository.PublishOpenAiConfigurationAsync(
            normalized,
            Hash(normalized.IdempotencyKey),
            Hash(ConfigurationMaterial(normalized)),
            nowUtc,
            cancellationToken);
    }

    private static void ValidatePolicy(
        AiEmbeddingProviderPolicyCommand value,
        DateTimeOffset nowUtc)
    {
        if (value.SuperAdminUserPublicId == Guid.Empty ||
            !CodePattern().IsMatch(value.Code) ||
            value.Version is < 1 or > 1_000_000 ||
            value.ModelCode is not ("text-embedding-3-small" or "text-embedding-3-large") ||
            !RegionEndpoints.TryGetValue(value.DataResidencyCode, out var expectedEndpoint) ||
            !string.Equals(value.EndpointOrigin, expectedEndpoint, StringComparison.Ordinal) ||
            value.DpaReferenceHash.Length != 32 || value.TermsSnapshotHash.Length != 32 ||
            value.InputTokenCostUsdPerMillion is < 0 or > 1000 ||
            value.ApprovedAtUtc.Offset != TimeSpan.Zero || value.ApprovedAtUtc > nowUtc ||
            value.ExpiresAtUtc.Offset != TimeSpan.Zero || value.ExpiresAtUtc <= nowUtc ||
            value.ExpiresAtUtc > nowUtc.AddYears(2) ||
            !ValidIdempotencyKey(value.IdempotencyKey))
            throw new ArgumentException(
                "The governed OpenAI embedding policy is invalid or incomplete.");
    }

    private static void ValidateConfiguration(OpenAiSemanticConfigurationCommand value)
    {
        if (value.SuperAdminUserPublicId == Guid.Empty ||
            value.ProviderPolicyPublicId == Guid.Empty ||
            !CodePattern().IsMatch(value.Code) || value.Version is < 1 or > 1_000_000 ||
            value.MaximumBatchSize is < 1 or > 64 ||
            value.MaximumCostUsdPerEmbedding is < 0.000001m or > 1m ||
            value.MonthlyBudgetUsd < value.MaximumCostUsdPerEmbedding ||
            value.MonthlyBudgetUsd > 10_000m ||
            !ValidIdempotencyKey(value.IdempotencyKey))
            throw new ArgumentException(
                "The governed OpenAI semantic configuration is invalid or incomplete.");
    }

    private static string NormalizeOrigin(string? value)
    {
        if (!Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) ||
            uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment) || !string.IsNullOrEmpty(uri.UserInfo))
            throw new ArgumentException("Provider endpoint must be an exact HTTPS origin.");
        return uri.GetLeftPart(UriPartial.Authority);
    }

    private static bool ValidIdempotencyKey(string value) =>
        value.Length is >= 16 and <= 128 && !value.Any(char.IsControl);

    private static byte[] Hash(string value) => SHA256.HashData(Encoding.UTF8.GetBytes(value));

    private static string PolicyMaterial(AiEmbeddingProviderPolicyCommand value) => Frame
    (
        "AiEmbeddingProviderPolicy/v1",
        value.SuperAdminUserPublicId.ToString("D"), value.Code,
        value.Version.ToString(CultureInfo.InvariantCulture), value.ModelCode,
        value.EndpointOrigin, value.DataResidencyCode,
        Convert.ToHexString(value.DpaReferenceHash),
        Convert.ToHexString(value.TermsSnapshotHash),
        value.InputTokenCostUsdPerMillion.ToString("0.000000", CultureInfo.InvariantCulture),
        value.ApprovedAtUtc.UtcDateTime.ToString("O", CultureInfo.InvariantCulture),
        value.ExpiresAtUtc.UtcDateTime.ToString("O", CultureInfo.InvariantCulture)
    );

    private static string ConfigurationMaterial(OpenAiSemanticConfigurationCommand value) => Frame
    (
        "OpenAiSemanticConfiguration/v1",
        value.SuperAdminUserPublicId.ToString("D"),
        value.ProviderPolicyPublicId.ToString("D"), value.Code,
        value.Version.ToString(CultureInfo.InvariantCulture),
        value.MaximumBatchSize.ToString(CultureInfo.InvariantCulture),
        value.MaximumCostUsdPerEmbedding.ToString("0.000000", CultureInfo.InvariantCulture),
        value.MonthlyBudgetUsd.ToString("0.000000", CultureInfo.InvariantCulture)
    );

    private static string Frame(params string[] values)
    {
        var builder = new StringBuilder();
        foreach (var value in values)
            builder.Append(value.Length.ToString(CultureInfo.InvariantCulture))
                .Append(':').Append(value).Append('\n');
        return builder.ToString();
    }

    [GeneratedRegex("^[a-z0-9](?:[a-z0-9._-]{0,48}[a-z0-9])?$",
        RegexOptions.CultureInvariant)]
    private static partial Regex CodePattern();
}

public sealed class AiProviderGovernanceAdministrationDataException(
    string operation,
    int databaseErrorNumber,
    Exception? innerException = null) : Exception(
        $"AI provider governance operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
