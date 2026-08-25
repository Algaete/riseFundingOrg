using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public interface IAiExplanationProcessingRepository
{
    Task<AiExplanationJobLease?> ClaimAsync(
        string workerInstanceId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<AiExplanationInput?> GetInputAsync(
        Guid jobPublicId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<bool> RenewLeaseAsync(
        Guid jobPublicId,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task CompleteAsync(
        AiExplanationJobLease lease,
        AiExplanationGeneration generation,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task FailAsync(
        Guid jobPublicId,
        Guid leaseId,
        string safeCode,
        bool retryable,
        SemanticProviderCallAccounting providerCallAccounting,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);
}

public interface IAiExplanationAdministrationRepository
{
    Task<(bool Succeeded, string Code, bool WasReplay, AiExplanationRunSummary? Run)> CreateAsync(
        Guid adminUserPublicId,
        Guid sourceSemanticEvaluationRunPublicId,
        string explanationConfigurationVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        bool runtimeEnabled,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<AiExplanationRunDetail?> GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken);
}

public interface IStructuredExplanationService
{
    Task<AiExplanationGeneration> GenerateAsync(
        AiStructuredExplanationRequest request,
        CancellationToken cancellationToken);
}

public sealed record AiStructuredExplanationRequest(
    string ExplanationConfigurationVersion,
    byte[] ConfigurationFingerprint,
    string ProviderCode,
    string ModelCode,
    string InputSchemaVersion,
    string OutputSchemaVersion,
    string PromptVersion,
    byte[] PromptFingerprint,
    byte[] ResponseSchemaFingerprint,
    short MaximumOutputTokens,
    decimal MaximumCostUsd,
    string CanonicalInputJson,
    byte[] InputContentHash,
    AiProviderGovernanceContext ProviderGovernance);

public sealed class AiExplanationProviderException : Exception
{
    public AiExplanationProviderException(
        string safeCode,
        bool retryable,
        Exception? innerException = null,
        SemanticProviderCallAccounting providerCallAccounting =
            SemanticProviderCallAccounting.ChargeUncertain)
        : base("Structured explanation provider failed.", innerException)
    {
        SafeCode = safeCode;
        Retryable = retryable;
        ProviderCallAccounting = providerCallAccounting;
    }

    public string SafeCode { get; }
    public bool Retryable { get; }
    public SemanticProviderCallAccounting ProviderCallAccounting { get; }
}
