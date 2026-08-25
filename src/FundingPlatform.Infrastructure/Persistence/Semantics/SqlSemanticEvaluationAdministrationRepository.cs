using System.Data;
using Dapper;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlSemanticProcessingRepository : ISemanticEvaluationRepository
{
    public async Task<SemanticEvaluationRunMutation> CreateAsync(
        Guid adminUserPublicId,
        string evaluationSetVersion,
        string semanticConfigurationVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        bool runtimeEnabled,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("EvaluationSetVersion", evaluationSetVersion, DbType.String, size: 64);
        parameters.Add(
            "SemanticConfigurationVersion",
            semanticConfigurationVersion,
            DbType.String,
            size: 64);
        parameters.Add("IdempotencyKeyHash", idempotencyKeyHash, DbType.Binary, size: 32);
        parameters.Add("RequestHash", requestHash, DbType.Binary, size: 32);
        parameters.Add("RuntimeEnabled", runtimeEnabled, DbType.Boolean);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<EvaluationMutationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_SemanticEvaluationRun_Create",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 120,
                    cancellationToken: cancellationToken));
            var summary = row.Succeeded ? MapSummary(row) : null;
            return new SemanticEvaluationRunMutation(
                row.Succeeded,
                NormalizeMutationCode(row.Code),
                summary,
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw Wrap("create semantic evaluation run", exception);
        }
    }

    public async Task<SemanticEvaluationRunPage> ListAsync(
        Guid adminUserPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("PageNumber", page, DbType.Int32);
        parameters.Add("PageSize", pageSize, DbType.Int32);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEvaluationRun_List",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<EvaluationPageMetadataRow>();
            var rows = await reader.ReadAsync<EvaluationSummaryRow>();
            return new SemanticEvaluationRunPage(
                rows.Select(MapSummary).ToArray(),
                metadata.TotalCount,
                page,
                pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list semantic evaluation runs", exception);
        }
    }

    public async Task<SemanticEvaluationRunDetail?> GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEvaluationRun_Get",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            var run = await reader.ReadSingleOrDefaultAsync<EvaluationSummaryRow>();
            if (run is null) return null;
            var counts = await reader.ReadSingleAsync<EvaluationEmbeddingCountsRow>();
            return new SemanticEvaluationRunDetail(
                MapSummary(run),
                counts.QueuedEmbeddingJobCount,
                counts.ProcessingEmbeddingJobCount,
                counts.SucceededEmbeddingJobCount,
                counts.RetryScheduledEmbeddingJobCount,
                counts.PermanentFailedEmbeddingJobCount,
                counts.SkippedStaleEmbeddingJobCount,
                counts.RejectedInputEmbeddingJobCount);
        }
        catch (SqlException exception)
        {
            throw Wrap("read semantic evaluation run", exception);
        }
    }

    public async Task<SemanticEvaluationRunReport?> GetReportAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEvaluationRun_Report",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            var run = await reader.ReadSingleOrDefaultAsync<EvaluationSummaryRow>();
            if (run is null) return null;
            var summary = MapSummary(run);
            var splits = (await reader.ReadAsync<EvaluationSplitReportRow>()).ToArray();
            if (!ValidReport(summary, splits))
            {
                throw new SemanticProcessingDataException(
                    "validate semantic evaluation report",
                    -1,
                    new InvalidDataException(
                        "Semantic evaluation report aggregate contract drifted."));
            }
            return new SemanticEvaluationRunReport(
                summary,
                splits.Select(row => new SemanticEvaluationSplitReport(
                    row.DatasetSplit,
                    row.PairCount,
                    row.EvaluatedCount,
                    row.LabelledCount,
                    row.RelevantLabelCount,
                    row.CoveragePercentage,
                    row.RecallAt10,
                    row.NormalizedDiscountedCumulativeGainAt10,
                    row.BaselineNormalizedDiscountedCumulativeGainAt10,
                    row.NormalizedDiscountedCumulativeGainDelta,
                    row.MeanReciprocalRankAt10,
                    row.MeanRankDelta)).ToArray());
        }
        catch (SqlException exception)
        {
            throw Wrap("read semantic evaluation report", exception);
        }
    }

    private static bool ValidReport(
        SemanticEvaluationRunSummary run,
        IReadOnlyList<EvaluationSplitReportRow> splits)
    {
        if (splits.Count is < 1 or > 2 ||
            splits.Select(row => row.DatasetSplit).Distinct().Count() != splits.Count ||
            splits.Any(row =>
                row.DatasetSplit > 1 || row.PairCount <= 0 ||
                row.EvaluatedCount < 0 || row.EvaluatedCount > row.PairCount ||
                row.LabelledCount != row.EvaluatedCount ||
                row.RelevantLabelCount < 0 || row.RelevantLabelCount > row.PairCount ||
                row.CoveragePercentage is < 0 or > 100 ||
                row.DatasetSplit == 0 &&
                (row.RecallAt10.HasValue ||
                 row.NormalizedDiscountedCumulativeGainAt10.HasValue ||
                 row.BaselineNormalizedDiscountedCumulativeGainAt10.HasValue ||
                 row.NormalizedDiscountedCumulativeGainDelta.HasValue ||
                 row.MeanReciprocalRankAt10.HasValue || row.MeanRankDelta.HasValue)))
        {
            return false;
        }

        try
        {
            return splits.Sum(row => row.PairCount) == run.PairCount &&
                   splits.Sum(row => row.EvaluatedCount) == run.EvaluatedCount &&
                   splits.Sum(row => row.LabelledCount) == run.LabelledCount;
        }
        catch (OverflowException)
        {
            return false;
        }
    }

    private static SemanticEvaluationRunSummary MapSummary(EvaluationSummaryRow row) => new(
        row.PublicId,
        (SemanticEvaluationRunStatus)row.Status,
        row.EvaluationSetVersion,
        row.SemanticConfigurationVersion,
        row.ProviderCode,
        row.ModelCode,
        row.Dimensions,
        row.PurposeCode,
        row.NormalizationVersion,
        row.ProjectCount,
        row.OpportunityCount,
        row.PairCount,
        row.PrimaryCohortCount,
        row.EvaluatedCount,
        row.LabelledCount,
        new SemanticEvaluationMetrics(
            row.CoveragePercentage,
            row.ProviderSuccessPercentage,
            row.RecallAt10,
            row.NormalizedDiscountedCumulativeGainAt10,
            row.BaselineNormalizedDiscountedCumulativeGainAt10,
            row.NormalizedDiscountedCumulativeGainDelta,
            row.MeanReciprocalRankAt10,
            row.MeanRankDelta,
            row.TotalEstimatedCostUsd,
            row.LatencyP95Milliseconds,
            row.HardGatePromotionCount,
            row.MeetsPromotionGate),
        ToUtc(row.CreatedAtUtc),
        ToUtc(row.StartedAtUtc),
        ToUtc(row.CompletedAtUtc),
        NormalizeErrorCode(row.LastErrorCode));

    private static string NormalizeMutationCode(string? value) => value switch
    {
        "queued" or "replayed" or "semantic-processing-disabled" or "not-found" or
        "active-evaluation-exists" or "budget-insufficient" or
        "configuration-not-approved" or "eval-set-not-ready" => value,
        _ => "operation-failed"
    };

    private static string? NormalizeErrorCode(string? value) => value switch
    {
        null => null,
        "semantic-configuration-invalid" or "semantic-work-invalid" or
        "semantic-embedding-permanent-failure" or "semantic-evaluation-error" or
        "lease-expired" or "internal-error" => value,
        _ => "internal-error"
    };

    private class EvaluationSummaryRow
    {
        public Guid PublicId { get; init; }
        public byte Status { get; init; }
        public string EvaluationSetVersion { get; init; } = "";
        public string SemanticConfigurationVersion { get; init; } = "";
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public int Dimensions { get; init; }
        public string PurposeCode { get; init; } = "";
        public string NormalizationVersion { get; init; } = "";
        public int ProjectCount { get; init; }
        public int OpportunityCount { get; init; }
        public int PairCount { get; init; }
        public int PrimaryCohortCount { get; init; }
        public int EvaluatedCount { get; init; }
        public int LabelledCount { get; init; }
        public decimal? CoveragePercentage { get; init; }
        public decimal? ProviderSuccessPercentage { get; init; }
        public decimal? RecallAt10 { get; init; }
        public decimal? NormalizedDiscountedCumulativeGainAt10 { get; init; }
        public decimal? BaselineNormalizedDiscountedCumulativeGainAt10 { get; init; }
        public decimal? NormalizedDiscountedCumulativeGainDelta { get; init; }
        public decimal? MeanReciprocalRankAt10 { get; init; }
        public decimal? MeanRankDelta { get; init; }
        public decimal? TotalEstimatedCostUsd { get; init; }
        public int? LatencyP95Milliseconds { get; init; }
        public int? HardGatePromotionCount { get; init; }
        public bool? MeetsPromotionGate { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? StartedAtUtc { get; init; }
        public DateTime? CompletedAtUtc { get; init; }
        public string? LastErrorCode { get; init; }
    }

    private sealed class EvaluationMutationRow : EvaluationSummaryRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public bool WasReplay { get; init; }
    }

    private sealed class EvaluationPageMetadataRow
    {
        public long TotalCount { get; init; }
    }

    private sealed class EvaluationEmbeddingCountsRow
    {
        public int QueuedEmbeddingJobCount { get; init; }
        public int ProcessingEmbeddingJobCount { get; init; }
        public int SucceededEmbeddingJobCount { get; init; }
        public int RetryScheduledEmbeddingJobCount { get; init; }
        public int PermanentFailedEmbeddingJobCount { get; init; }
        public int SkippedStaleEmbeddingJobCount { get; init; }
        public int RejectedInputEmbeddingJobCount { get; init; }
    }

    private sealed class EvaluationSplitReportRow
    {
        public byte DatasetSplit { get; init; }
        public long PairCount { get; init; }
        public long EvaluatedCount { get; init; }
        public long LabelledCount { get; init; }
        public long RelevantLabelCount { get; init; }
        public decimal CoveragePercentage { get; init; }
        public decimal? RecallAt10 { get; init; }
        public decimal? NormalizedDiscountedCumulativeGainAt10 { get; init; }
        public decimal? BaselineNormalizedDiscountedCumulativeGainAt10 { get; init; }
        public decimal? NormalizedDiscountedCumulativeGainDelta { get; init; }
        public decimal? MeanReciprocalRankAt10 { get; init; }
        public decimal? MeanRankDelta { get; init; }
    }
}
