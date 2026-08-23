using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Imports;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Imports;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Imports;

public sealed class SqlImportRunRepository(
    ISqlConnectionFactory connectionFactory) : IImportRunRepository
{
    public async Task<ImportRunCreateMutation> CreateManualAsync(
        Guid adminUserPublicId,
        int fundingSourceId,
        string keyword,
        int maximumResults,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        string correlationId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<CreateRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_Admin_Create",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    FundingSourceId = fundingSourceId,
                    Keyword = keyword,
                    MaximumResults = maximumResults,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    CorrelationId = correlationId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));

            var accepted = row.Succeeded && row.RunPublicId.HasValue
                ? new ImportRunAccepted(
                    row.RunPublicId.Value,
                    row.FundingSourceId,
                    row.SourceName ?? "Fuente",
                    (ImportRunStatus)row.Status!.Value,
                    ToUtc(row.CreatedAtUtc!.Value),
                    row.WasReplay)
                : null;
            return new ImportRunCreateMutation(row.Succeeded, row.Code, accepted);
        }
        catch (SqlException exception)
        {
            throw Wrap("create manual import run", exception);
        }
    }

    public async Task<ImportRunPage> ListAsync(
        Guid adminUserPublicId,
        int? fundingSourceId,
        ImportRunStatus? status,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_Admin_List",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    FundingSourceId = fundingSourceId,
                    Status = status.HasValue ? (byte?)status.Value : null,
                    PageNumber = page,
                    PageSize = pageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var total = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<SummaryRow>()).AsList();
            return new ImportRunPage(rows.Select(MapSummary).ToArray(), total, page, pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list import runs", exception);
        }
    }

    public async Task<ImportRunDetail?> GetAsync(
        Guid adminUserPublicId,
        Guid runId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_Admin_Get",
                new { AdminUserPublicId = adminUserPublicId, RunPublicId = runId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var header = await reader.ReadSingleAsync<DetailRow>();
            if (!header.Succeeded)
            {
                if (string.Equals(header.Code, "forbidden", StringComparison.OrdinalIgnoreCase))
                {
                    throw new ImportRunDataException(
                        "read import run", 51601,
                        new InvalidOperationException("Administrative access was denied."));
                }

                _ = await reader.ReadAsync<ItemRow>();
                _ = await reader.ReadAsync<ErrorRow>();
                return null;
            }

            var items = (await reader.ReadAsync<ItemRow>()).Select(MapItem).ToArray();
            var errors = (await reader.ReadAsync<ErrorRow>()).Select(MapError).ToArray();
            return new ImportRunDetail(
                header.RunPublicId!.Value,
                header.FundingSourceId!.Value,
                header.SourceName!,
                header.ProviderCode!,
                (ImportTriggerType)header.TriggerType!.Value,
                (ImportRunStatus)header.Status!.Value,
                header.Keyword!,
                header.MaximumResults!.Value,
                header.RetrievedCount!.Value,
                header.CreatedCount!.Value,
                header.UpdatedCount!.Value,
                header.UnchangedCount!.Value,
                header.StagedForReviewCount!.Value,
                header.FailedCount!.Value,
                header.AttemptCount!.Value,
                ToUtc(header.CreatedAtUtc!.Value),
                ToNullableUtc(header.StartedAtUtc),
                ToNullableUtc(header.CompletedAtUtc),
                header.LastErrorCode,
                items,
                errors);
        }
        catch (ImportRunDataException)
        {
            throw;
        }
        catch (SqlException exception)
        {
            throw Wrap("read import run", exception);
        }
    }

    public async Task<IReadOnlyList<ScheduledImportRun>> CreateDueScheduledAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<ScheduledRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_Scheduler_CreateDue",
                new { NowUtc = nowUtc.UtcDateTime, BatchSize = batchSize },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(row => new ScheduledImportRun(
                row.RunPublicId, row.FundingSourceId, row.ProviderCode)).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("schedule due import runs", exception);
        }
    }

    public async Task<IReadOnlyList<ScheduledImportRun>> RequeueStrandedAsync(
        DateTimeOffset nowUtc,
        int batchSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<ScheduledRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_RequeueStranded",
                new { NowUtc = nowUtc.UtcDateTime, BatchSize = batchSize },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(row => new ScheduledImportRun(
                row.RunPublicId, row.FundingSourceId, row.ProviderCode)).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("requeue stranded import runs", exception);
        }
    }

    public async Task<ImportRunClaimMutation> ClaimAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        ValidateLease(leaseId, leaseDuration);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<ClaimRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_Claim",
                new
                {
                    RunPublicId = runId,
                    LeaseId = leaseId,
                    LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            if (!row.Succeeded)
                return new ImportRunClaimMutation(false, NormalizeCode(row.Code));
            if (row.RunPublicId is null || row.FundingSourceId is null ||
                string.IsNullOrWhiteSpace(row.ProviderCode) || row.Keyword is null ||
                row.MaximumResults is null || row.RetrievedCount is null ||
                row.AttemptCount is null || row.RequestRateLimitPerMinute is < 1 or > 600 ||
                row.MaximumResponseBytes is < 4_096 or > 26_214_400 ||
                row.ContentRetentionDays is < 1 or > 3_650 ||
                row.AcquisitionPolicyVersion is null or < 1 ||
                row.AcquisitionPolicyFingerprint is not { Length: 32 })
                throw new ImportRunDataException(
                    "materialize governed import claim", -1,
                    new InvalidOperationException("The governed import claim was incomplete."));

            var requestRateLimitPerMinute = row.RequestRateLimitPerMinute.GetValueOrDefault();
            var maximumResponseBytes = row.MaximumResponseBytes.GetValueOrDefault();
            var contentRetentionDays = row.ContentRetentionDays.GetValueOrDefault();
            var acquisitionPolicyVersion = row.AcquisitionPolicyVersion.GetValueOrDefault();
            return new ImportRunClaimMutation(true, NormalizeCode(row.Code), new ImportRunClaim(
                    row.RunPublicId.Value,
                    row.FundingSourceId.Value,
                    row.ProviderCode,
                    row.Keyword,
                    row.MaximumResults.Value,
                    row.RetrievedCount.Value,
                    row.AttemptCount.Value,
                    leaseId,
                    requestRateLimitPerMinute,
                    maximumResponseBytes,
                    contentRetentionDays,
                    acquisitionPolicyVersion,
                    row.AcquisitionPolicyFingerprint));
        }
        catch (SqlException exception)
        {
            throw Wrap("claim import run", exception);
        }
    }

    public async Task<bool> RenewLeaseAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        TimeSpan leaseDuration,
        CancellationToken cancellationToken)
    {
        ValidateLease(leaseId, leaseDuration);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRun_RenewLease",
                new
                {
                    RunPublicId = runId,
                    LeaseId = leaseId,
                    LeaseSeconds = checked((int)leaseDuration.TotalSeconds),
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return row.Succeeded;
        }
        catch (SqlException exception)
        {
            throw Wrap("renew import run lease", exception);
        }
    }

    public async Task<IReadOnlyList<PendingImportRunItem>> ListPendingItemsAsync(
        Guid runId,
        Guid leaseId,
        int batchSize,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        if (batchSize is < 1 or > 25)
        {
            throw new ArgumentOutOfRangeException(nameof(batchSize));
        }

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<PendingItemRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_ImportRunItem_ListPending",
                new
                {
                    RunPublicId = runId,
                    LeaseId = leaseId,
                    BatchSize = batchSize,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return rows.Select(row => new PendingImportRunItem(
                row.ItemPublicId,
                row.RawObservationPublicId,
                row.ExternalId,
                row.NormalizedSnapshotVersion,
                row.NormalizedSnapshotJson,
                row.NormalizedSnapshotHash)).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("list pending import items", exception);
        }
    }

    public async Task<ImportObservationRecord> RecordObservationAsync(
        Guid runId,
        Guid leaseId,
        FundingSourceObservation observation,
        byte[] sourceItemKeyHash,
        CancellationToken cancellationToken)
    {
        var snapshot = FundingOpportunitySnapshotSerializer.Serialize(
            observation.Opportunity);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<ObservationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_RawFundingOpportunity_Record",
                new
                {
                    RunPublicId = runId,
                    LeaseId = leaseId,
                    observation.ExternalId,
                    observation.SourceUrl,
                    RetrievedAtUtc = observation.RetrievedAtUtc.UtcDateTime,
                    observation.MimeType,
                    RawContent = observation.RawJson,
                    observation.ContentHash,
                    SourceItemKeyHash = sourceItemKeyHash,
                    NormalizedSnapshotVersion = snapshot.Version,
                    NormalizedSnapshotJson = snapshot.Json,
                    NormalizedSnapshotHash = snapshot.Hash
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            EnsureSucceeded(row.Succeeded, row.Code, "record raw funding observation");
            return new ImportObservationRecord(
                row.ItemPublicId!.Value,
                row.RawObservationPublicId!.Value,
                row.WasRawReplay,
                row.AlreadyCompleted);
        }
        catch (SqlException exception)
        {
            throw Wrap("record raw funding observation", exception);
        }
    }

    public Task CompleteItemAsync(
        Guid runId,
        Guid leaseId,
        Guid itemId,
        Guid? opportunityId,
        FundingOpportunityUpsertOutcome outcome,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_ImportRunItem_Complete",
            new
            {
                RunPublicId = runId,
                LeaseId = leaseId,
                ItemPublicId = itemId,
                OutcomeCode = outcome switch
                {
                    FundingOpportunityUpsertOutcome.Created => "created",
                    FundingOpportunityUpsertOutcome.Updated => "updated",
                    FundingOpportunityUpsertOutcome.Unchanged => "unchanged",
                    FundingOpportunityUpsertOutcome.StagedForReview => "staged-for-review",
                    _ => throw new ArgumentOutOfRangeException(nameof(outcome))
                },
                OpportunityPublicId = opportunityId,
                CompletedAtUtc = completedAtUtc.UtcDateTime
            },
            "complete import item",
            cancellationToken);

    public Task FailItemAsync(
        Guid runId,
        Guid leaseId,
        Guid itemId,
        string stage,
        string errorCode,
        string safeMessage,
        bool isRetryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_ImportRunItem_Fail",
            new
            {
                RunPublicId = runId,
                LeaseId = leaseId,
                ItemPublicId = itemId,
                Stage = stage,
                ErrorCode = errorCode,
                SanitizedMessage = safeMessage,
                IsRetryable = isRetryable,
                OccurredAtUtc = failedAtUtc.UtcDateTime
            },
            "fail import item",
            cancellationToken);

    public Task CompleteRunAsync(
        Guid runId,
        Guid leaseId,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_ImportRun_Complete",
            new
            {
                RunPublicId = runId,
                LeaseId = leaseId,
                CompletedAtUtc = completedAtUtc.UtcDateTime
            },
            "complete import run",
            cancellationToken);

    public Task FailRunAsync(
        Guid runId,
        Guid leaseId,
        string stage,
        string errorCode,
        string safeMessage,
        bool isRetryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken) => ExecuteMutationAsync(
            "dbo.FundingPlatform_usp_ImportRun_Fail",
            new
            {
                RunPublicId = runId,
                LeaseId = leaseId,
                Stage = stage,
                ErrorCode = errorCode,
                SanitizedMessage = safeMessage,
                IsRetryable = isRetryable,
                FailedAtUtc = failedAtUtc.UtcDateTime
            },
            "fail import run",
            cancellationToken);

    private async Task ExecuteMutationAsync(
        string procedure,
        object parameters,
        string operation,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            EnsureSucceeded(row.Succeeded, row.Code, operation);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static ImportRunSummary MapSummary(SummaryRow row) => new(
        row.RunPublicId,
        row.FundingSourceId,
        row.SourceName,
        row.ProviderCode,
        (ImportTriggerType)row.TriggerType,
        (ImportRunStatus)row.Status,
        row.Keyword,
        row.MaximumResults,
        row.RetrievedCount,
        row.CreatedCount,
        row.UpdatedCount,
        row.UnchangedCount,
        row.StagedForReviewCount,
        row.FailedCount,
        ToUtc(row.CreatedAtUtc),
        ToNullableUtc(row.StartedAtUtc),
        ToNullableUtc(row.CompletedAtUtc),
        row.LastErrorCode);

    private static ImportRunItem MapItem(ItemRow row) => new(
        row.ItemPublicId,
        row.RawObservationPublicId,
        row.OpportunityPublicId,
        row.ExternalId,
        (ImportRunItemStatus)row.Status,
        row.OutcomeCode,
        ToUtc(row.CreatedAtUtc),
        ToNullableUtc(row.CompletedAtUtc),
        row.DuplicateCandidatePublicId,
        row.DuplicateCandidateStatus,
        row.DuplicateMatchKind,
        row.DuplicateConfidence,
        row.SuggestedCanonicalOpportunityPublicId,
        row.SuggestedCanonicalTitle,
        row.DuplicateDecisionPublicId,
        row.DuplicateDecision,
        row.DuplicateCandidateRowVersion);

    private static ImportRunError MapError(ErrorRow row) => new(
        row.ErrorPublicId,
        row.ItemPublicId,
        row.Stage,
        row.ErrorCode,
        row.SanitizedMessage,
        row.IsRetryable,
        ToUtc(row.OccurredAtUtc));

    private static void EnsureSucceeded(bool succeeded, string code, string operation)
    {
        if (!succeeded)
        {
            throw new InvalidOperationException(
                $"Import persistence rejected operation '{operation}' ({NormalizeCode(code)})." );
        }
    }

    private static string NormalizeCode(string? code) => code switch
    {
        "not-found" or "not-claimable" or "lease-lost" or "already-completed" or
            "already-failed" or "idempotency-conflict" or "source-disabled" or
            "provider-not-supported" or "retention-expired" or "claimed" => code,
        _ => "operation-rejected"
    };

    private static void ValidateLease(Guid leaseId, TimeSpan duration)
    {
        if (leaseId == Guid.Empty)
        {
            throw new ArgumentException("Lease identifier is invalid.", nameof(leaseId));
        }

        if (duration < TimeSpan.FromSeconds(30) || duration > TimeSpan.FromMinutes(30))
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }
    }

    private static ImportRunDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToNullableUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private sealed record CreateRow(
        bool Succeeded, string Code, Guid? RunPublicId, int FundingSourceId,
        string? SourceName, byte? Status, DateTime? CreatedAtUtc, bool WasReplay);

    private record SummaryRow(
        Guid RunPublicId, int FundingSourceId, string SourceName, string ProviderCode,
        byte TriggerType, byte Status, string Keyword, int MaximumResults,
        int RetrievedCount, int CreatedCount, int UpdatedCount, int UnchangedCount,
        int StagedForReviewCount, int FailedCount, DateTime CreatedAtUtc,
        DateTime? StartedAtUtc, DateTime? CompletedAtUtc, string? LastErrorCode);

    private sealed record DetailRow(
        bool Succeeded, string Code, Guid? RunPublicId, int? FundingSourceId,
        string? SourceName, string? ProviderCode, byte? TriggerType, byte? Status,
        string? Keyword, int? MaximumResults, int? RetrievedCount, int? CreatedCount,
        int? UpdatedCount, int? UnchangedCount, int? StagedForReviewCount, int? FailedCount,
        short? AttemptCount, DateTime? CreatedAtUtc, DateTime? StartedAtUtc,
        DateTime? CompletedAtUtc, string? LastErrorCode);

    private sealed record ItemRow(
        Guid ItemPublicId, Guid? RawObservationPublicId, Guid? OpportunityPublicId,
        string ExternalId, byte Status, string? OutcomeCode, DateTime CreatedAtUtc,
        DateTime? CompletedAtUtc, Guid? DuplicateCandidatePublicId,
        byte? DuplicateCandidateStatus, byte? DuplicateMatchKind,
        decimal? DuplicateConfidence, Guid? SuggestedCanonicalOpportunityPublicId,
        string? SuggestedCanonicalTitle, Guid? DuplicateDecisionPublicId,
        byte? DuplicateDecision, byte[]? DuplicateCandidateRowVersion);

    private sealed record ErrorRow(
        Guid ErrorPublicId, Guid? ItemPublicId, string Stage, string ErrorCode,
        string SanitizedMessage, bool IsRetryable, DateTime OccurredAtUtc);

    private sealed record ScheduledRow(
        Guid RunPublicId, int FundingSourceId, string ProviderCode);

    private sealed record ClaimRow(
        bool Succeeded, string Code, Guid? RunPublicId, int? FundingSourceId,
        string? ProviderCode, string? Keyword, int? MaximumResults, short? AttemptCount,
        int? RetrievedCount, DateTime? LeaseUntilUtc,
        int? RequestRateLimitPerMinute, int? MaximumResponseBytes,
        short? ContentRetentionDays, int? AcquisitionPolicyVersion,
        byte[]? AcquisitionPolicyFingerprint);

    private sealed record ObservationRow(
        bool Succeeded, string Code, Guid? ItemPublicId, Guid? RawObservationPublicId,
        bool WasRawReplay, bool AlreadyCompleted);

    private sealed record PendingItemRow(
        Guid ItemPublicId,
        Guid RawObservationPublicId,
        string ExternalId,
        short NormalizedSnapshotVersion,
        string NormalizedSnapshotJson,
        byte[] NormalizedSnapshotHash);

    private sealed class MutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
    }
}
