using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public interface ISemanticProcessingRepository
{
    Task<IReadOnlyList<SemanticEmbeddingJobLease>> ClaimEmbeddingJobsAsync(
        string workerInstanceId,
        int batchSize,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<SemanticEmbeddingInput?> GetEmbeddingInputAsync(
        Guid jobPublicId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<bool> RenewEmbeddingJobLeaseAsync(
        Guid jobPublicId,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task CompleteEmbeddingJobAsync(
        Guid jobPublicId,
        Guid leaseId,
        Guid budgetReservationPublicId,
        SemanticEmbeddingGeneration generation,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task FailEmbeddingJobAsync(
        Guid jobPublicId,
        Guid leaseId,
        string errorCode,
        bool retryable,
        SemanticProviderCallAccounting providerCallAccounting,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);

    Task<IReadOnlyList<SemanticShadowEvaluationRunLease>> ClaimShadowEvaluationRunsAsync(
        string workerInstanceId,
        int batchSize,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<bool> RenewShadowEvaluationRunLeaseAsync(
        Guid runPublicId,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<SemanticShadowEvaluationWorkState?> GetShadowEvaluationWorkStateAsync(
        Guid runPublicId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task CompleteShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken);

    Task ReleaseShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        string reasonCode,
        DateTimeOffset nextAttemptAtUtc,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task FailShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        string errorCode,
        bool retryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken);
}

public interface ISemanticEvaluationRepository
{
    Task<SemanticEvaluationRunMutation> CreateAsync(
        Guid adminUserPublicId,
        string evaluationSetVersion,
        string semanticConfigurationVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        bool runtimeEnabled,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken);

    Task<SemanticEvaluationRunPage> ListAsync(
        Guid adminUserPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken);

    Task<SemanticEvaluationRunDetail?> GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken);

    Task<SemanticEvaluationRunReport?> GetReportAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken);
}

public interface IEmbeddingService
{
    Task<SemanticEmbeddingGeneration> GenerateAsync(
        SemanticEmbeddingRequest request,
        CancellationToken cancellationToken);
}

public sealed record SemanticEmbeddingRequest(
    SemanticSubjectType SubjectType,
    Guid SubjectPublicId,
    int SubjectVersion,
    string SemanticConfigurationVersion,
    byte[] SemanticConfigurationFingerprint,
    string ProviderCode,
    string ModelCode,
    string PurposeCode,
    string TemplateVersion,
    string NormalizationVersion,
    int Dimensions,
    string CanonicalInputJson,
    byte[] InputContentHash,
    decimal MaximumCostUsd,
    AiProviderGovernanceContext? ProviderGovernance);

public sealed class SemanticProcessingDataException(
    string operation,
    int databaseErrorNumber,
    Exception innerException) : Exception(
        $"Semantic processing data operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public string Operation { get; } = operation;
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}

public sealed class SemanticEmbeddingException : Exception
{
    public SemanticEmbeddingException(
        string safeCode,
        bool retryable,
        Exception? innerException = null,
        SemanticProviderCallAccounting providerCallAccounting =
            SemanticProviderCallAccounting.ChargeUncertain)
        : base("Semantic embedding generation failed.", innerException)
    {
        SafeCode = safeCode;
        Retryable = retryable;
        ProviderCallAccounting = providerCallAccounting;
    }

    public string SafeCode { get; }
    public bool Retryable { get; }
    public SemanticProviderCallAccounting ProviderCallAccounting { get; }
}
