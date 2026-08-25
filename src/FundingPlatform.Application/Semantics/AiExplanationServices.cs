using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public sealed record AiExplanationProcessingPolicy(
    bool Enabled,
    int BatchSize,
    TimeSpan LeaseDuration,
    TimeSpan ItemTimeout)
{
    public void Validate()
    {
        if (BatchSize is < 1 or > 4 ||
            LeaseDuration < TimeSpan.FromMinutes(5) ||
            LeaseDuration > TimeSpan.FromMinutes(30) ||
            ItemTimeout < TimeSpan.FromSeconds(10) ||
            ItemTimeout > TimeSpan.FromMinutes(3) ||
            LeaseDuration < ItemTimeout + TimeSpan.FromMinutes(2))
            throw new InvalidOperationException(
                "Structured explanation worker limits are unsafe.");
    }
}

public sealed class AiExplanationProcessingService(
    IAiExplanationProcessingRepository repository,
    IStructuredExplanationService provider,
    AiExplanationProcessingPolicy policy,
    TimeProvider timeProvider,
    string workerInstanceId)
{
    private static readonly HashSet<string> FailureCodes =
    [
        "explanation-provider-unavailable",
        "explanation-provider-throttled",
        "explanation-provider-timeout",
        "explanation-provider-invalid-response",
        "explanation-input-invalid",
        "explanation-configuration-invalid",
        "internal-error"
    ];

    public async Task<SemanticProcessingBatchResult> ProcessAsync(
        CancellationToken cancellationToken)
    {
        policy.Validate();
        if (!policy.Enabled) return new SemanticProcessingBatchResult(0, 0, 0);
        if (string.IsNullOrWhiteSpace(workerInstanceId) || workerInstanceId.Length > 100 ||
            workerInstanceId.Any(char.IsControl))
            throw new InvalidOperationException("Structured explanation worker identity is invalid.");

        var claimed = 0;
        var completed = 0;
        var failed = 0;
        var deferred = 0;
        var skipped = 0;
        for (var index = 0; index < policy.BatchSize; index++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var lease = await repository.ClaimAsync(
                workerInstanceId,
                policy.LeaseDuration,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (lease is null) break;
            claimed++;
            if (!ValidLease(lease))
            {
                await FailAsync(
                    lease,
                    "explanation-configuration-invalid",
                    retryable: false,
                    SemanticProviderCallAccounting.NotInvoked,
                    cancellationToken);
                failed++;
                continue;
            }

            AiExplanationInput? input;
            try
            {
                input = await repository.GetInputAsync(
                    lease.JobPublicId,
                    lease.LeaseId,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
            }
            catch (Exception) when (!cancellationToken.IsCancellationRequested)
            {
                await FailAsync(
                    lease,
                    "explanation-input-invalid",
                    retryable: false,
                    SemanticProviderCallAccounting.NotInvoked,
                    cancellationToken);
                failed++;
                continue;
            }
            if (input is null)
            {
                skipped++;
                continue;
            }
            if (!ValidInput(lease, input))
            {
                await FailAsync(
                    lease,
                    "explanation-input-invalid",
                    retryable: false,
                    SemanticProviderCallAccounting.NotInvoked,
                    cancellationToken);
                failed++;
                continue;
            }
            if (!await repository.RenewLeaseAsync(
                    lease.JobPublicId,
                    lease.LeaseId,
                    policy.LeaseDuration,
                    timeProvider.GetUtcNow(),
                    cancellationToken))
            {
                deferred++;
                continue;
            }

            AiExplanationGeneration generation;
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                    cancellationToken);
                timeout.CancelAfter(policy.ItemTimeout);
                generation = await provider.GenerateAsync(
                    new AiStructuredExplanationRequest(
                        lease.ExplanationConfigurationVersion,
                        lease.ConfigurationFingerprint,
                        lease.ProviderCode,
                        lease.ModelCode,
                        lease.InputSchemaVersion,
                        lease.OutputSchemaVersion,
                        lease.PromptVersion,
                        lease.PromptFingerprint,
                        lease.ResponseSchemaFingerprint,
                        lease.MaximumOutputTokens,
                        lease.MaximumCostUsdPerResult,
                        input.CanonicalInputJson,
                        input.InputContentHash,
                        input.ProviderGovernance),
                    timeout.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                await FailAsync(
                    lease,
                    "explanation-provider-timeout",
                    Retryable(lease),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }
            catch (AiExplanationProviderException exception)
            {
                await FailAsync(
                    lease,
                    FailureCodes.Contains(exception.SafeCode)
                        ? exception.SafeCode
                        : "explanation-provider-unavailable",
                    exception.Retryable && Retryable(lease),
                    exception.ProviderCallAccounting,
                    cancellationToken);
                failed++;
                continue;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                await FailAsync(
                    lease,
                    "explanation-provider-unavailable",
                    Retryable(lease),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }

            if (!ValidGeneration(lease, generation))
            {
                await FailAsync(
                    lease,
                    "explanation-provider-invalid-response",
                    Retryable(lease),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }
            if (await TryCompleteAsync(lease, generation, cancellationToken)) completed++;
            else deferred++;
        }
        return new SemanticProcessingBatchResult(
            claimed, completed, failed, deferred, skipped);
    }

    private async Task FailAsync(
        AiExplanationJobLease lease,
        string code,
        bool retryable,
        SemanticProviderCallAccounting accounting,
        CancellationToken cancellationToken) =>
        await repository.FailAsync(
            lease.JobPublicId,
            lease.LeaseId,
            code,
            retryable,
            accounting,
            timeProvider.GetUtcNow(),
            cancellationToken);

    private async Task<bool> TryCompleteAsync(
        AiExplanationJobLease lease,
        AiExplanationGeneration generation,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var renewed = await repository.RenewLeaseAsync(
                lease.JobPublicId,
                lease.LeaseId,
                policy.LeaseDuration,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (!renewed && attempt == 0) return false;
            try
            {
                await repository.CompleteAsync(
                    lease, generation, timeProvider.GetUtcNow(), cancellationToken);
                return true;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception) when (attempt == 0)
            {
                // Replay the exact immutable output once after an ambiguous ACK.
            }
            catch (Exception)
            {
                return false;
            }
        }
        return false;
    }

    private static bool Retryable(AiExplanationJobLease lease) =>
        lease.AttemptCount < lease.MaximumAttempts;

    private static bool ValidLease(AiExplanationJobLease lease) =>
        lease.JobPublicId != Guid.Empty && lease.LeaseId != Guid.Empty &&
        lease.BudgetReservationPublicId != Guid.Empty &&
        lease.ExplanationRunPublicId != Guid.Empty &&
        lease.ExplanationConfigurationVersion.Length is >= 3 and <= 64 &&
        lease.ConfigurationFingerprint is { Length: 32 } &&
        lease.ProviderCode == "openai" && lease.ModelCode == "gpt-5.6-sol" &&
        lease.InputSchemaVersion == "explanation-input-v1" &&
        lease.OutputSchemaVersion == "explanation-output-v1" &&
        lease.PromptVersion == "explanation-review-es-v1" &&
        lease.PromptFingerprint is { Length: 32 } &&
        lease.ResponseSchemaFingerprint is { Length: 32 } &&
        lease.MaximumInputUtf8Bytes == 8192 &&
        lease.MaximumOutputTokens is >= 128 and <= 1024 &&
        lease.MaximumAttempts is >= 1 and <= 3 &&
        lease.MaximumCostUsdPerResult is >= 0.000001m and <= 1m &&
        lease.InputContentHash is { Length: 32 } &&
        lease.AttemptCount is >= 1 and <= 3;

    private static bool ValidInput(AiExplanationJobLease lease, AiExplanationInput input)
    {
        var utf8 = Encoding.UTF8.GetBytes(input.CanonicalInputJson);
        return input.JobPublicId == lease.JobPublicId &&
               input.LeaseId == lease.LeaseId &&
               input.InputContentHash is { Length: 32 } &&
               CryptographicOperations.FixedTimeEquals(
                   input.InputContentHash, lease.InputContentHash) &&
               CryptographicOperations.FixedTimeEquals(
                   SHA256.HashData(utf8), lease.InputContentHash) &&
               utf8.Length is > 2 and <= 8192 &&
               AiExplanationInputPolicy.IsCanonicalAndSafe(input.CanonicalInputJson) &&
               input.ProviderGovernance is
               {
                   Capability: 1,
                   RetentionMode: AiProviderRetentionMode.ZeroDataRetention,
                   MaximumProviderRetentionDays: 0,
                   ExternalProcessingAllowed: true,
                   PolicyFingerprint.Length: 32
               };
    }

    private static bool ValidGeneration(
        AiExplanationJobLease lease,
        AiExplanationGeneration generation)
    {
        if (generation.ProviderCode != lease.ProviderCode ||
            generation.ModelCode != lease.ModelCode ||
            generation.PromptVersion != lease.PromptVersion ||
            generation.OutputSchemaVersion != lease.OutputSchemaVersion ||
            generation.OutputFingerprint is not { Length: 32 } ||
            generation.ProviderRequestIdHash is { Length: not 32 } ||
            generation.InputTokens is < 0 or > 8192 ||
            generation.OutputTokens is < 0 || generation.OutputTokens > lease.MaximumOutputTokens ||
            generation.EstimatedCostUsd is < 0.000001m ||
            generation.EstimatedCostUsd > lease.MaximumCostUsdPerResult ||
            generation.LatencyMilliseconds is < 0 or > 600_000 ||
            !AiExplanationOutputPolicy.IsSafe(
                generation.Assessment,
                generation.Summary,
                generation.PrimaryReasonCode,
                generation.CitedRuleCodes))
            return false;
        var citedJson = JsonSerializer.Serialize(generation.CitedRuleCodes);
        var material = string.Join('|',
            ((byte)generation.Assessment).ToString(
                System.Globalization.CultureInfo.InvariantCulture),
            generation.Summary,
            generation.PrimaryReasonCode,
            citedJson,
            Convert.ToHexString(lease.ConfigurationFingerprint));
        return CryptographicOperations.FixedTimeEquals(
            SHA256.HashData(Encoding.Unicode.GetBytes(material)),
            generation.OutputFingerprint);
    }
}

public static partial class AiExplanationOutputPolicy
{
    public static readonly IReadOnlySet<string> ReasonCodes = new HashSet<string>(
        [
            "signals-aligned",
            "semantic-high-hard-gate-conflict",
            "semantic-low-structured-compatible",
            "insufficient-structured-evidence"
        ],
        StringComparer.Ordinal);

    public static readonly IReadOnlySet<string> RuleCodes = new HashSet<string>(
        [
            "geography", "organization_type", "legal_entity", "operating_years",
            "prior_experience", "categories", "beneficiaries", "project_type", "amount"
        ],
        StringComparer.Ordinal);

    public static bool IsSafe(
        AiExplanationAssessment assessment,
        string? summary,
        string? primaryReasonCode,
        IReadOnlyList<string>? citedRuleCodes)
    {
        if (!Enum.IsDefined(assessment) || summary is null ||
            summary.Length is < 1 or > 300 || summary != summary.Trim() ||
            summary.Any(char.IsControl) || EmailPattern().IsMatch(summary) ||
            UrlPattern().IsMatch(summary) || RutPattern().IsMatch(summary) ||
            primaryReasonCode is null || !ReasonCodes.Contains(primaryReasonCode) ||
            !ReasonMatchesAssessment(assessment, primaryReasonCode) ||
            citedRuleCodes is null || citedRuleCodes.Count > 3 ||
            citedRuleCodes.Any(code => !RuleCodes.Contains(code)) ||
            citedRuleCodes.Distinct(StringComparer.Ordinal).Count() != citedRuleCodes.Count ||
            !citedRuleCodes.SequenceEqual(
                citedRuleCodes.Order(StringComparer.Ordinal), StringComparer.Ordinal))
            return false;
        return true;
    }

    private static bool ReasonMatchesAssessment(
        AiExplanationAssessment assessment,
        string reasonCode) => assessment switch
    {
        AiExplanationAssessment.Aligned => reasonCode == "signals-aligned",
        AiExplanationAssessment.Conflict =>
            reasonCode is "semantic-high-hard-gate-conflict" or
                "semantic-low-structured-compatible",
        AiExplanationAssessment.Insufficient =>
            reasonCode == "insufficient-structured-evidence",
        _ => false
    };

    [GeneratedRegex(@"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", RegexOptions.CultureInvariant)]
    private static partial Regex EmailPattern();

    [GeneratedRegex(@"(?:https?://|www\.)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex UrlPattern();

    [GeneratedRegex(@"\b(?:\d{1,2}\.\d{3}\.\d{3}|\d{7,8})-[0-9Kk]\b",
        RegexOptions.CultureInvariant)]
    private static partial Regex RutPattern();
}

public sealed class AiExplanationAdministrationService(
    IAiExplanationAdministrationRepository repository,
    AiExplanationProcessingPolicy policy,
    TimeProvider timeProvider)
{
    public async Task<SemanticEvaluationResult<AiExplanationRunSummary>> CreateAsync(
        Guid adminUserPublicId,
        Guid sourceSemanticEvaluationRunPublicId,
        string? configurationVersion,
        string? idempotencyKey,
        CancellationToken cancellationToken)
    {
        var version = NormalizeVersion(configurationVersion);
        var key = idempotencyKey?.Trim() ?? string.Empty;
        if (adminUserPublicId == Guid.Empty ||
            sourceSemanticEvaluationRunPublicId == Guid.Empty ||
            version is null || key.Length is < 16 or > 128 || key.Any(char.IsControl))
            return new SemanticEvaluationResult<AiExplanationRunSummary>(
                SemanticEvaluationOutcome.Invalid,
                Code: "invalid-request",
                Errors: new Dictionary<string, string[]>
                {
                    ["request"] = ["La solicitud de explicación en sombra no es válida."]
                });
        policy.Validate();
        var keyHash = SHA256.HashData(Encoding.UTF8.GetBytes(key));
        var requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Join('\n',
            "ai-explanation-run-create-v1",
            sourceSemanticEvaluationRunPublicId.ToString("D"),
            version)));
        try
        {
            var mutation = await repository.CreateAsync(
                adminUserPublicId,
                sourceSemanticEvaluationRunPublicId,
                version,
                keyHash,
                requestHash,
                policy.Enabled,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (mutation.Succeeded && mutation.Run is not null &&
                SafeSummary(mutation.Run))
                return new SemanticEvaluationResult<AiExplanationRunSummary>(
                    SemanticEvaluationOutcome.Success, mutation.Run, mutation.Code);
            return new SemanticEvaluationResult<AiExplanationRunSummary>(
                mutation.Code switch
                {
                    "active-run-exists" or "idempotency-conflict" =>
                        SemanticEvaluationOutcome.Conflict,
                    "budget-insufficient" or "source-or-configuration-not-ready" =>
                        SemanticEvaluationOutcome.Invalid,
                    _ => SemanticEvaluationOutcome.Unavailable
                },
                Code: mutation.Code);
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<AiExplanationRunSummary>(
                exception.DatabaseErrorNumber is 51601 or 51602 or 54424
                    ? SemanticEvaluationOutcome.Forbidden
                    : exception.DatabaseErrorNumber == 54425
                        ? SemanticEvaluationOutcome.Conflict
                        : SemanticEvaluationOutcome.Unavailable,
                Code: exception.DatabaseErrorNumber == 54425
                    ? "idempotency-conflict"
                    : "persistence-unavailable");
        }
    }

    public async Task<SemanticEvaluationResult<AiExplanationRunDetail>> GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        if (adminUserPublicId == Guid.Empty || runPublicId == Guid.Empty ||
            page is < 1 or > 10_000 || pageSize is < 1 or > 50)
            return new SemanticEvaluationResult<AiExplanationRunDetail>(
                SemanticEvaluationOutcome.Invalid,
                Code: "invalid-query",
                Errors: new Dictionary<string, string[]>
                {
                    ["query"] = ["La consulta de explicación en sombra no es válida."]
                });
        try
        {
            var detail = await repository.GetAsync(
                adminUserPublicId, runPublicId, page, pageSize, cancellationToken);
            if (detail is null)
                return new SemanticEvaluationResult<AiExplanationRunDetail>(
                    SemanticEvaluationOutcome.NotFound, Code: "not-found");
            if (!SafeSummary(detail.Run) || detail.ResultCount < detail.Results.Count ||
                detail.Page < 1 || detail.PageSize is < 1 or > 50 ||
                detail.Results.Count > detail.PageSize ||
                detail.Results.Any(result => result.CaseOrdinal < 1) ||
                detail.Results.Select(result => result.CaseOrdinal).Distinct().Count() !=
                    detail.Results.Count ||
                detail.Results.Any(result => !SafeResult(result)))
                return new SemanticEvaluationResult<AiExplanationRunDetail>(
                    SemanticEvaluationOutcome.Unavailable, Code: "explanation-data-invalid");
            return new SemanticEvaluationResult<AiExplanationRunDetail>(
                SemanticEvaluationOutcome.Success, detail);
        }
        catch (SemanticProcessingDataException exception)
        {
            return new SemanticEvaluationResult<AiExplanationRunDetail>(
                exception.DatabaseErrorNumber is 51601 or 51602 or 54424
                    ? SemanticEvaluationOutcome.Forbidden
                    : SemanticEvaluationOutcome.Unavailable,
                Code: "persistence-unavailable");
        }
    }

    private static bool SafeSummary(AiExplanationRunSummary run) =>
        run.PublicId != Guid.Empty &&
        run.SourceSemanticEvaluationRunPublicId != Guid.Empty &&
        Enum.IsDefined(run.Status) &&
        run.ExplanationConfigurationVersion.Length is >= 3 and <= 64 &&
        run.ProviderCode == "openai" && run.ModelCode == "gpt-5.6-sol" &&
        run.ItemCount is >= 1 and <= 300 &&
        run.CompletedCount >= 0 && run.FailedCount >= 0 &&
        run.CompletedCount + run.FailedCount <= run.ItemCount &&
        (run.Status == AiExplanationRunStatus.Processing
            ? run.CompletedAtUtc is null && run.TotalEstimatedCostUsd is null
            : run.CompletedAtUtc is not null &&
              run.TotalEstimatedCostUsd is not null &&
              run.CompletedCount + run.FailedCount == run.ItemCount) &&
        (run.TotalEstimatedCostUsd is null or >= 0 and <= 10_000m);

    private static bool SafeResult(AiExplanationResultItem result) =>
        result.InputTokens is >= 0 and <= 8192 &&
        result.OutputTokens is >= 0 and <= 1024 &&
        result.EstimatedCostUsd is >= 0.000001m and <= 1m &&
        result.LatencyMilliseconds is >= 0 and <= 600_000 &&
        result.CreatedAtUtc.Offset == TimeSpan.Zero &&
        AiExplanationOutputPolicy.IsSafe(
            result.Assessment,
            result.Summary,
            result.PrimaryReasonCode,
            result.CitedRuleCodes);

    private static string? NormalizeVersion(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized is { Length: >= 3 and <= 64 } &&
               char.IsAsciiLetterOrDigit(normalized[0]) &&
               normalized.All(character =>
                   char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.')
            ? normalized
            : null;
    }
}
