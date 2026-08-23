using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Imports;

namespace FundingPlatform.Application.Imports;

public enum ImportRunProcessingOutcome
{
    Completed,
    Ignored,
    Failed
}

public sealed record ImportRunProcessingResult(
    ImportRunProcessingOutcome Outcome,
    Guid RunId,
    int ProcessedCount = 0,
    int FailedCount = 0,
    string? Code = null);

public sealed class ImportRunLeaseLostException(Guid runId) : Exception(
    $"The durable import lease for run '{runId:D}' was lost before processing completed.")
{
    public Guid RunId { get; } = runId;
    public string Code => "lease-lost";
}

public sealed class ImportRunProcessingService(
    IImportRunRepository importRuns,
    IFundingSourceProviderRegistry providers,
    IFundingOpportunityRepository opportunities,
    TimeProvider timeProvider,
    TimeSpan leaseDuration,
    TimeSpan? leaseRenewalInterval = null)
{
    private const int MaximumRawJsonBytes = 1_048_576;
    private readonly TimeSpan renewalInterval = ResolveRenewalInterval(
        leaseDuration, leaseRenewalInterval);

    public async Task<ImportRunProcessingResult> ProcessAsync(
        Guid runId,
        CancellationToken cancellationToken)
    {
        if (runId == Guid.Empty)
        {
            return new ImportRunProcessingResult(
                ImportRunProcessingOutcome.Ignored, runId, Code: "invalid-run-id");
        }

        var now = timeProvider.GetUtcNow();
        var leaseId = Guid.NewGuid();
        var claimMutation = await importRuns.ClaimAsync(
            runId, leaseId, now, leaseDuration, cancellationToken);
        if (!claimMutation.Succeeded || claimMutation.Claim is null)
        {
            return new ImportRunProcessingResult(
                claimMutation.Code is "provider-not-supported" or "retention-expired" or
                    "policy-changed"
                    ? ImportRunProcessingOutcome.Failed
                    : ImportRunProcessingOutcome.Ignored,
                runId,
                Code: claimMutation.Code);
        }
        var claim = claimMutation.Claim;

        await using var heartbeat = new LeaseHeartbeat(
            importRuns,
            claim,
            timeProvider,
            leaseDuration,
            renewalInterval);
        using var operation = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken, heartbeat.LeaseLostToken);
        try
        {
            return await ProcessClaimedAsync(claim, heartbeat, operation.Token);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (OperationCanceledException) when (heartbeat.LeaseLostToken.IsCancellationRequested)
        {
            // Let the QueueTrigger abandon this delivery. A later delivery can claim
            // the run after the old lease expires; the watchdog remains a backstop.
            throw new ImportRunLeaseLostException(runId);
        }
        finally
        {
            await heartbeat.StopAsync();
        }
    }

    private async Task<ImportRunProcessingResult> ProcessClaimedAsync(
        ImportRunClaim claim,
        LeaseHeartbeat heartbeat,
        CancellationToken cancellationToken)
    {
        var runId = claim.RunId;
        if (!providers.TryGet(claim.ProviderCode, out var provider))
        {
            await heartbeat.StopAsync();
            await importRuns.FailRunAsync(
                runId,
                claim.LeaseId,
                "ProviderResolution",
                "provider-not-allowlisted",
                "La fuente configurada no está habilitada en este worker.",
                false,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return new ImportRunProcessingResult(
                ImportRunProcessingOutcome.Failed, runId, Code: "provider-not-allowlisted");
        }

        if (!string.Equals(
                claim.ProviderCode, provider.Source.ProviderCode, StringComparison.Ordinal))
        {
            await heartbeat.StopAsync();
            await importRuns.FailRunAsync(
                runId,
                claim.LeaseId,
                "ProviderResolution",
                "provider-metadata-mismatch",
                "La configuración de la fuente no coincide con el proveedor registrado.",
                false,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return new ImportRunProcessingResult(
                ImportRunProcessingOutcome.Failed, runId, Code: "provider-metadata-mismatch");
        }

        var processed = 0;
        var failed = 0;
        var rehydratedExternalIds = new HashSet<string>(StringComparer.Ordinal);
        var pendingItems = await importRuns.ListPendingItemsAsync(
            runId,
            claim.LeaseId,
            claim.MaximumResults,
            timeProvider.GetUtcNow(),
            cancellationToken);
        foreach (var pending in pendingItems)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!FundingOpportunitySnapshotSerializer.TryDeserialize(
                    pending.SnapshotVersion,
                    pending.SnapshotJson,
                    pending.SnapshotHash,
                    out var pendingOpportunity) ||
                !string.Equals(
                    pending.ExternalId, pendingOpportunity.ExternalId, StringComparison.Ordinal) ||
                !string.Equals(
                    claim.ProviderCode, pendingOpportunity.ProviderCode, StringComparison.Ordinal))
            {
                failed++;
                await heartbeat.StopAsync();
                await importRuns.FailRunAsync(
                    runId,
                    claim.LeaseId,
                    "PendingSnapshot",
                    "pending-snapshot-invalid",
                    "Un elemento pendiente no pudo rehidratarse de forma segura.",
                    false,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return new ImportRunProcessingResult(
                    ImportRunProcessingOutcome.Failed,
                    runId,
                    processed,
                    failed,
                    "pending-snapshot-invalid");
            }

            try
            {
                var upsert = await opportunities.UpsertExternalWithIdentityAsync(
                    claim.FundingSourceId,
                    claim.ProviderCode,
                    pendingOpportunity,
                    cancellationToken);
                await importRuns.CompleteItemAsync(
                    runId,
                    claim.LeaseId,
                    pending.ItemId,
                    upsert.OpportunityId,
                    upsert.Outcome,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                rehydratedExternalIds.Add(pending.ExternalId);
                processed++;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                failed++;
                await heartbeat.StopAsync();
                await importRuns.FailRunAsync(
                    runId,
                    claim.LeaseId,
                    "StageExternal",
                    "editorial-staging-failed",
                    "El elemento durable no pudo prepararse y se reintentará.",
                    true,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return new ImportRunProcessingResult(
                    ImportRunProcessingOutcome.Failed,
                    runId,
                    processed,
                    failed,
                    "editorial-staging-failed");
            }
        }

        var remainingSlots = Math.Max(0, claim.MaximumResults - claim.RetrievedCount);
        IReadOnlyList<FundingSourceObservation> observations;
        try
        {
            observations = remainingSlots == 0
                ? []
                : await provider.FetchOpenAsync(
                    claim.Keyword,
                    claim.MaximumResults,
                    new GovernedAcquisitionContext(
                        claim.FundingSourceId,
                        claim.RequestRateLimitPerMinute,
                        claim.MaximumResponseBytes,
                        claim.ContentRetentionDays,
                        claim.AcquisitionPolicyVersion,
                        claim.AcquisitionPolicyFingerprint),
                    cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            await heartbeat.StopAsync();
            await importRuns.FailRunAsync(
                runId,
                claim.LeaseId,
                "Fetch",
                "source-fetch-failed",
                "No fue posible obtener datos de la fuente en este intento.",
                true,
                timeProvider.GetUtcNow(),
                cancellationToken);
            return new ImportRunProcessingResult(
                ImportRunProcessingOutcome.Failed, runId, Code: "source-fetch-failed");
        }

        // Persist the whole fetched window before attempting any editorial write.
        // A staging failure must not leave the rest of an already fetched batch only
        // in process memory: every accepted observation can then be rehydrated from
        // its immutable normalized snapshot on the next claim.
        var stagingCandidates = new List<DurableStageCandidate>();
        var candidateIndexes = new Dictionary<Guid, int>();
        foreach (var observation in observations.Take(claim.MaximumResults))
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (rehydratedExternalIds.Contains(observation.ExternalId))
            {
                continue;
            }

            if (remainingSlots == 0)
            {
                break;
            }

            if (!TryValidateObservation(provider.Source.ProviderCode, observation, out var errorCode))
            {
                failed++;
                await heartbeat.StopAsync();
                await importRuns.FailRunAsync(
                    runId,
                    claim.LeaseId,
                    "RawValidation",
                    errorCode,
                    "La fuente devolvió una observación que no cumple el contrato seguro.",
                    false,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return new ImportRunProcessingResult(
                    ImportRunProcessingOutcome.Failed, runId, processed, failed,
                    errorCode);
            }

            var sourceItemKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(
                $"{provider.Source.ProviderCode}\n{observation.ExternalId}"));
            ImportObservationRecord record;
            try
            {
                // This durable write always precedes editorial staging.
                record = await importRuns.RecordObservationAsync(
                    runId, claim.LeaseId, observation, sourceItemKeyHash, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                failed++;
                await heartbeat.StopAsync();
                await importRuns.FailRunAsync(
                    runId,
                    claim.LeaseId,
                    "RawPersistence",
                    "raw-persistence-failed",
                    "No fue posible conservar una observación de la fuente.",
                    true,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return new ImportRunProcessingResult(
                    ImportRunProcessingOutcome.Failed, runId, processed, failed,
                    "raw-persistence-failed");
            }

            if (record.IsAlreadyCompleted)
            {
                processed++;
                continue;
            }

            if (candidateIndexes.TryGetValue(record.ItemId, out var candidateIndex))
            {
                var duplicate = stagingCandidates[candidateIndex];
                stagingCandidates[candidateIndex] = duplicate with
                {
                    ObservationCount = duplicate.ObservationCount + 1
                };
                continue;
            }

            remainingSlots--;
            candidateIndexes.Add(record.ItemId, stagingCandidates.Count);
            stagingCandidates.Add(new DurableStageCandidate(
                record.ItemId,
                observation.Opportunity,
                1));
        }

        foreach (var candidate in stagingCandidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var upsert = await opportunities.UpsertExternalWithIdentityAsync(
                    claim.FundingSourceId,
                    claim.ProviderCode,
                    candidate.Opportunity,
                    cancellationToken);
                await importRuns.CompleteItemAsync(
                    runId,
                    claim.LeaseId,
                    candidate.ItemId,
                    upsert.OpportunityId,
                    upsert.Outcome,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                processed += candidate.ObservationCount;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception)
            {
                failed++;
                await heartbeat.StopAsync();
                await importRuns.FailRunAsync(
                    runId,
                    claim.LeaseId,
                    "StageExternal",
                    "editorial-staging-failed",
                    "La observación quedó almacenada y se reintentará su preparación editorial.",
                    true,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
                return new ImportRunProcessingResult(
                    ImportRunProcessingOutcome.Failed,
                    runId,
                    processed,
                    failed,
                    "editorial-staging-failed");
            }
        }

        await heartbeat.StopAsync();
        await importRuns.CompleteRunAsync(
            runId, claim.LeaseId, timeProvider.GetUtcNow(), cancellationToken);
        return new ImportRunProcessingResult(
            ImportRunProcessingOutcome.Completed, runId, processed, failed,
            failed == 0 ? "completed" : "partial");
    }

    private sealed record DurableStageCandidate(
        Guid ItemId,
        ExternalFundingOpportunity Opportunity,
        int ObservationCount);

    private static TimeSpan ResolveRenewalInterval(
        TimeSpan duration,
        TimeSpan? configuredInterval)
    {
        if (duration < TimeSpan.FromSeconds(30) || duration > TimeSpan.FromMinutes(30))
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }

        var interval = configuredInterval ?? TimeSpan.FromTicks(Math.Min(
            duration.Ticks / 3,
            TimeSpan.FromMinutes(5).Ticks));
        if (interval <= TimeSpan.Zero || interval >= duration)
        {
            throw new ArgumentOutOfRangeException(nameof(configuredInterval));
        }

        return interval;
    }

    private static bool TryValidateObservation(
        string providerCode,
        FundingSourceObservation? observation,
        out string errorCode)
    {
        errorCode = "invalid-observation";
        if (observation is null ||
            string.IsNullOrWhiteSpace(observation.ExternalId) ||
            observation.ExternalId.Length > 250 ||
            string.IsNullOrWhiteSpace(observation.SourceUrl) ||
            observation.SourceUrl.Length > 2048 ||
            string.IsNullOrWhiteSpace(observation.RawJson) ||
            observation.ContentHash is not { Length: 32 } ||
            observation.Opportunity is null ||
            !string.Equals(
                providerCode, observation.Opportunity.ProviderCode, StringComparison.Ordinal) ||
            !string.Equals(
                observation.ExternalId, observation.Opportunity.ExternalId, StringComparison.Ordinal) ||
            !string.Equals(
                observation.SourceUrl, observation.Opportunity.SourceUrl, StringComparison.Ordinal))
        {
            return false;
        }

        var rawBytes = Encoding.UTF8.GetBytes(observation.RawJson);
        if (rawBytes.Length > MaximumRawJsonBytes)
        {
            errorCode = "raw-content-too-large";
            return false;
        }

        var actualHash = SHA256.HashData(rawBytes);
        if (!CryptographicOperations.FixedTimeEquals(actualHash, observation.ContentHash))
        {
            errorCode = "raw-content-hash-mismatch";
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(observation.RawJson, new JsonDocumentOptions
            {
                AllowTrailingCommas = false,
                CommentHandling = JsonCommentHandling.Disallow,
                MaxDepth = 64
            });
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                errorCode = "raw-content-invalid-json";
                return false;
            }
        }
        catch (JsonException)
        {
            errorCode = "raw-content-invalid-json";
            return false;
        }

        return true;
    }

    private sealed class LeaseHeartbeat : IAsyncDisposable
    {
        private readonly IImportRunRepository repository;
        private readonly ImportRunClaim claim;
        private readonly TimeProvider timeProvider;
        private readonly TimeSpan leaseDuration;
        private readonly TimeSpan interval;
        private readonly CancellationTokenSource stop = new();
        private readonly CancellationTokenSource leaseLost = new();
        private readonly Task loop;
        private int stopping;

        public LeaseHeartbeat(
            IImportRunRepository repository,
            ImportRunClaim claim,
            TimeProvider timeProvider,
            TimeSpan leaseDuration,
            TimeSpan interval)
        {
            this.repository = repository;
            this.claim = claim;
            this.timeProvider = timeProvider;
            this.leaseDuration = leaseDuration;
            this.interval = interval;
            loop = RunAsync();
        }

        public CancellationToken LeaseLostToken => leaseLost.Token;

        public async Task StopAsync()
        {
            if (Interlocked.Exchange(ref stopping, 1) == 0)
            {
                await stop.CancelAsync();
            }

            await loop;
        }

        public async ValueTask DisposeAsync()
        {
            await StopAsync();
            stop.Dispose();
            leaseLost.Dispose();
        }

        private async Task RunAsync()
        {
            try
            {
                while (true)
                {
                    await Task.Delay(interval, timeProvider, stop.Token);
                    var renewed = await repository.RenewLeaseAsync(
                        claim.RunId,
                        claim.LeaseId,
                        timeProvider.GetUtcNow(),
                        leaseDuration,
                        stop.Token);
                    if (!renewed)
                    {
                        await leaseLost.CancelAsync();
                        return;
                    }
                }
            }
            catch (OperationCanceledException) when (stop.IsCancellationRequested)
            {
                // Normal shutdown before a terminal run mutation.
            }
            catch (Exception)
            {
                // Renewal details are intentionally not propagated or persisted.
                await leaseLost.CancelAsync();
            }
        }
    }
}
