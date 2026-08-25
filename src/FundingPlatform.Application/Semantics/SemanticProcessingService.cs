using FundingPlatform.Core.Semantics;

namespace FundingPlatform.Application.Semantics;

public sealed class SemanticProcessingService(
    ISemanticProcessingRepository repository,
    IEmbeddingService embeddingService,
    SemanticProcessingPolicy policy,
    TimeProvider timeProvider,
    string workerInstanceId)
{
    private static readonly HashSet<string> ProviderFailureCodes =
    [
        "embedding-provider-unavailable",
        "embedding-provider-throttled",
        "embedding-provider-timeout",
        "embedding-provider-invalid-response"
    ];

    public async Task<SemanticProcessingBatchResult> ProcessEmbeddingsAsync(
        CancellationToken cancellationToken)
    {
        policy.Validate();
        if (!policy.Enabled) return new SemanticProcessingBatchResult(0, 0, 0);
        ValidateWorkerInstanceId();
        cancellationToken.ThrowIfCancellationRequested();

        var claimed = 0;
        var cycleLimit = policy.BatchSize;
        var completed = 0;
        var failed = 0;
        var deferred = 0;
        var skipped = 0;
        for (var position = 0; position < cycleLimit; position++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            // Claim just in time. Provider work is serial, so batch-wide leases would
            // age while earlier calls run and consume attempts before later items start.
            var jobs = await repository.ClaimEmbeddingJobsAsync(
                workerInstanceId,
                1,
                policy.LeaseDuration,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (jobs.Count > 1)
            {
                throw new InvalidOperationException(
                    "Semantic repository returned more than one just-in-time lease.");
            }

            if (jobs.Count == 0) break;
            claimed++;
            var job = jobs[0];
            if (!ValidLease(job))
            {
                if (job.JobPublicId != Guid.Empty && job.LeaseId != Guid.Empty)
                {
                    await FailAsync(
                        job,
                        "semantic-job-invalid",
                        false,
                        SemanticProviderCallAccounting.NotInvoked,
                        cancellationToken);
                    failed++;
                }
                else
                {
                    // A malformed repository identity cannot be safely mutated.
                    deferred++;
                }
                continue;
            }
            if (position == 0)
                cycleLimit = Math.Min(cycleLimit, job.MaximumBatchSize);

            if (!await repository.RenewEmbeddingJobLeaseAsync(
                    job.JobPublicId,
                    job.LeaseId,
                    policy.LeaseDuration,
                    timeProvider.GetUtcNow(),
                    cancellationToken))
            {
                deferred++;
                continue;
            }

            SemanticEmbeddingInput? input;
            try
            {
                input = await repository.GetEmbeddingInputAsync(
                    job.JobPublicId, job.LeaseId, timeProvider.GetUtcNow(), cancellationToken);
            }
            catch (SemanticProcessingDataException exception)
                when (exception.DatabaseErrorNumber is 54111 or 54112)
            {
                await FailAsync(
                    job,
                    exception.DatabaseErrorNumber == 54111
                        ? "semantic-input-privacy-rejected"
                        : "semantic-input-hash-mismatch",
                    false,
                    SemanticProviderCallAccounting.NotInvoked,
                    cancellationToken);
                failed++;
                continue;
            }
            if (input is null)
            {
                // The database either lost the lease or terminalized stale/unsafe input and
                // released its pre-call reservation atomically. Do not mutate an old lease.
                skipped++;
                continue;
            }

            if (!SemanticInputPolicy.TryValidate(input, job, policy, out var inputError))
            {
                await FailAsync(
                    job,
                    inputError,
                    false,
                    SemanticProviderCallAccounting.NotInvoked,
                    cancellationToken);
                failed++;
                continue;
            }

            var template = job.TemplateVersion;
            SemanticEmbeddingGeneration generation;
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(policy.ItemTimeout);
                generation = await embeddingService.GenerateAsync(
                    new SemanticEmbeddingRequest(
                        job.SubjectType,
                        job.SubjectPublicId,
                        job.SubjectVersion,
                        job.SemanticConfigurationVersion,
                        job.SemanticConfigurationFingerprint,
                        job.ProviderCode,
                        job.ModelCode,
                        job.PurposeCode,
                        template,
                        job.NormalizationVersion,
                        job.Dimensions,
                        input.CanonicalText,
                        input.InputContentHash),
                    timeout.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                await FailAsync(
                    job,
                    "embedding-provider-timeout",
                    Retryable(job),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }
            catch (SemanticEmbeddingException exception)
            {
                var code = ProviderFailureCodes.Contains(exception.SafeCode)
                    ? exception.SafeCode
                    : "embedding-provider-unavailable";
                await FailAsync(
                    job,
                    code,
                    exception.Retryable && Retryable(job),
                    SemanticProviderCallAccounting.ChargeUncertain,
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
                    job,
                    "embedding-provider-unavailable",
                    Retryable(job),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }

            if (!ValidGeneration(generation, job))
            {
                await FailAsync(
                    job, "embedding-provider-invalid-response", Retryable(job),
                    SemanticProviderCallAccounting.ChargeUncertain,
                    cancellationToken);
                failed++;
                continue;
            }

            if (await TryCompleteEmbeddingAsync(
                    job, generation, cancellationToken))
            {
                completed++;
            }
            else
            {
                // Completion is idempotent. One replay resolves the common
                // commit-then-connection-loss case. If both attempts are ambiguous,
                // retain the lease/reservation; expiry accounts the maximum cost.
                deferred++;
            }
        }

        return new SemanticProcessingBatchResult(
            claimed, completed, failed, deferred, skipped);
    }

    public async Task<SemanticProcessingBatchResult> ProcessShadowEvaluationsAsync(
        CancellationToken cancellationToken)
    {
        policy.Validate();
        if (!policy.Enabled) return new SemanticProcessingBatchResult(0, 0, 0);
        ValidateWorkerInstanceId();
        cancellationToken.ThrowIfCancellationRequested();

        var runs = await repository.ClaimShadowEvaluationRunsAsync(
            workerInstanceId,
            1,
            policy.LeaseDuration,
            timeProvider.GetUtcNow(),
            cancellationToken);
        if (runs.Count > 1)
        {
            throw new InvalidOperationException("Semantic repository returned concurrent evaluation runs.");
        }

        var completed = 0;
        var failed = 0;
        var deferred = 0;
        foreach (var run in runs)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!ValidShadowConfiguration(run))
            {
                if (run.RunPublicId != Guid.Empty && run.LeaseId != Guid.Empty)
                {
                    await repository.FailShadowEvaluationRunAsync(
                        run.RunPublicId,
                        run.LeaseId,
                        "semantic-configuration-invalid",
                        false,
                        timeProvider.GetUtcNow(),
                        cancellationToken);
                    failed++;
                }
                else
                {
                    deferred++;
                }
                continue;
            }

            if (!await repository.RenewShadowEvaluationRunLeaseAsync(
                    run.RunPublicId,
                    run.LeaseId,
                    policy.LeaseDuration,
                    timeProvider.GetUtcNow(),
                    cancellationToken))
            {
                deferred++;
                continue;
            }

            var work = await repository.GetShadowEvaluationWorkStateAsync(
                run.RunPublicId,
                run.LeaseId,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (work is null)
            {
                // A missing work row means the lease was lost or SQL deliberately did
                // not expose work. Mutating that lease would turn readiness polling into
                // an attempt/failure, so leave it for the durable queue to reconcile.
                deferred++;
                continue;
            }

            if (work.RunPublicId != run.RunPublicId ||
                work.LeaseId != run.LeaseId || work.PairCount != run.PairCount ||
                work.ReadyPairCount is < 0 || work.ReadyPairCount > work.PairCount ||
                work.PendingEmbeddingJobCount < 0 ||
                work.PermanentFailedEmbeddingJobCount < 0)
            {
                await repository.FailShadowEvaluationRunAsync(
                    run.RunPublicId,
                    run.LeaseId,
                    "semantic-work-invalid",
                    false,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                failed++;
                continue;
            }

            if (work.PendingEmbeddingJobCount == 0)
            {
                // A terminal provider failure is an evaluation result, not an engine
                // failure. SQL completes a conservative partial report: missing pairs
                // lower coverage/success and can never improve ranking or promotion.
                if (await TryCompleteShadowEvaluationAsync(run, cancellationToken))
                    completed++;
                else
                    deferred++;
            }
            else
            {
                var now = timeProvider.GetUtcNow();
                await repository.ReleaseShadowEvaluationRunAsync(
                    run.RunPublicId,
                    run.LeaseId,
                    "semantic-embeddings-pending",
                    now.AddMinutes(1),
                    now,
                    cancellationToken);
                deferred++;
            }
        }

        return new SemanticProcessingBatchResult(runs.Count, completed, failed, deferred);
    }

    private bool ValidLease(SemanticEmbeddingJobLease job) =>
        job.JobPublicId != Guid.Empty && job.LeaseId != Guid.Empty &&
        job.BudgetReservationPublicId != Guid.Empty &&
        job.SubjectPublicId != Guid.Empty && job.SubjectVersion > 0 &&
        Enum.IsDefined(job.SubjectType) &&
        SafeCode(job.SemanticConfigurationVersion, 64) &&
        job.SemanticConfigurationFingerprint is { Length: 32 } &&
        SafeCode(job.ProviderCode, 50) && SafeCode(job.ModelCode, 128) &&
        job.Dimensions == policy.Dimensions && job.PurposeCode == policy.PurposeCode &&
        job.NormalizationVersion == policy.NormalizationVersion &&
        job.TemplateVersion == (job.SubjectType == SemanticSubjectType.Project
            ? policy.ProjectTemplateVersion
            : policy.OpportunityTemplateVersion) &&
        job.MaximumInputUtf8Bytes == policy.MaximumInputUtf8Bytes &&
        job.MaximumBatchSize is >= 1 and <= SemanticProcessingPolicy.MaximumBatchSize &&
        job.MaximumAttempts == policy.MaximumAttempts &&
        job.MaximumCostUsdPerEmbedding is >= 0 and <= 1 &&
        job.InputContentHash is { Length: 32 } &&
        job.AttemptCount is >= 1 && job.AttemptCount <= job.MaximumAttempts;

    private bool ValidGeneration(
        SemanticEmbeddingGeneration? generation,
        SemanticEmbeddingJobLease job) =>
        generation is not null &&
        generation.ProviderCode == job.ProviderCode && generation.ModelCode == job.ModelCode &&
        generation.TemplateVersion == job.TemplateVersion &&
        generation.Dimensions == job.Dimensions &&
        generation.Vector is { Length: SemanticProcessingPolicy.RequiredDimensions } &&
        generation.Vector.All(float.IsFinite) && generation.Vector.Any(value => value != 0) &&
        (!generation.InputTokens.HasValue ||
         generation.InputTokens is >= 0 && generation.InputTokens <= job.MaximumInputUtf8Bytes) &&
        (!generation.OutputTokens.HasValue ||
         generation.OutputTokens is >= 0 && generation.OutputTokens <= job.MaximumInputUtf8Bytes) &&
        generation.EstimatedCostUsd >= 0 &&
        generation.EstimatedCostUsd <= job.MaximumCostUsdPerEmbedding &&
        generation.ProviderRequestIdHash is null or { Length: 32 } &&
        generation.LatencyMilliseconds is >= 0 and <= 30_000;

    private bool ValidShadowConfiguration(SemanticShadowEvaluationRunLease run) =>
        run.RunPublicId != Guid.Empty && run.LeaseId != Guid.Empty &&
        SafeCode(run.SemanticConfigurationVersion, 64) &&
        run.SemanticConfigurationFingerprint is { Length: 32 } &&
        SafeCode(run.ProviderCode, 50) && SafeCode(run.ModelCode, 128) &&
        run.PurposeCode == policy.PurposeCode &&
        run.NormalizationVersion == policy.NormalizationVersion &&
        run.ProjectTemplateVersion == policy.ProjectTemplateVersion &&
        run.OpportunityTemplateVersion == policy.OpportunityTemplateVersion &&
        run.CalibrationVersion == policy.CalibrationVersion &&
        run.DistanceMetric == 1 && run.MaximumAttempts == policy.MaximumAttempts &&
        run.Dimensions == policy.Dimensions && run.PairCount is >= 300 and <= 5_000 &&
        run.AttemptCount is >= 1 and <= 3;

    private Task FailAsync(
        SemanticEmbeddingJobLease job,
        string code,
        bool retryable,
        SemanticProviderCallAccounting providerCallAccounting,
        CancellationToken cancellationToken) => repository.FailEmbeddingJobAsync(
            job.JobPublicId,
            job.LeaseId,
            code,
            retryable,
            providerCallAccounting,
            timeProvider.GetUtcNow(),
            cancellationToken);

    private bool Retryable(SemanticEmbeddingJobLease job) =>
        job.AttemptCount < job.MaximumAttempts;

    private async Task<bool> TryCompleteEmbeddingAsync(
        SemanticEmbeddingJobLease job,
        SemanticEmbeddingGeneration generation,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var renewed = await repository.RenewEmbeddingJobLeaseAsync(
                job.JobPublicId,
                job.LeaseId,
                policy.LeaseDuration,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (!renewed && attempt == 0) return false;

            try
            {
                await repository.CompleteEmbeddingJobAsync(
                    job.JobPublicId,
                    job.LeaseId,
                    job.BudgetReservationPublicId,
                    generation,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return true;
            }
            catch (SemanticProcessingDataException) when (attempt == 0)
            {
                // Retry the exact immutable completion coordinates once.
            }
            catch (SemanticProcessingDataException)
            {
                return false;
            }
        }

        return false;
    }

    private async Task<bool> TryCompleteShadowEvaluationAsync(
        SemanticShadowEvaluationRunLease run,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 2; attempt++)
        {
            var renewed = await repository.RenewShadowEvaluationRunLeaseAsync(
                run.RunPublicId,
                run.LeaseId,
                policy.LeaseDuration,
                timeProvider.GetUtcNow(),
                cancellationToken);
            if (!renewed && attempt == 0) return false;

            try
            {
                await repository.CompleteShadowEvaluationRunAsync(
                    run.RunPublicId,
                    run.LeaseId,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return true;
            }
            catch (SemanticProcessingDataException) when (attempt == 0)
            {
                // Renew when possible, then replay the exact server-side calculation.
                // If the first call committed, renewal returns false but Complete's
                // terminal replay contract still reconciles the lost acknowledgement.
            }
            catch (SemanticProcessingDataException)
            {
                return false;
            }
        }

        return false;
    }

    private void ValidateWorkerInstanceId()
    {
        if (!SafeCode(workerInstanceId, 128))
        {
            throw new InvalidOperationException("Semantic worker identity is invalid.");
        }
    }

    private static bool SafeCode(string? value, int maximumLength) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= maximumLength &&
        value.All(character =>
            char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');
}
