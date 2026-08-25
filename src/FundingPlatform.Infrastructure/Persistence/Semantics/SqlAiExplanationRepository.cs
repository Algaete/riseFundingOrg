using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlSemanticProcessingRepository :
    IAiExplanationProcessingRepository,
    IAiExplanationAdministrationRepository
{
    public async Task<AiExplanationJobLease?> ClaimAsync(
        string workerInstanceId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("WorkerInstanceId", workerInstanceId, DbType.String, size: 100);
        parameters.Add("LeaseSeconds", CheckedSeconds(leaseDuration), DbType.Int32);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<ExplanationLeaseRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationJob_Claim",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row is null ? null : Map(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("claim structured explanation job", exception);
        }
    }

    public async Task<AiExplanationInput?> GetInputAsync(
        Guid jobPublicId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("JobPublicId", jobPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<ExplanationInputRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationJob_GetInput",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row is null
                ? null
                : new AiExplanationInput(
                    row.JobPublicId,
                    row.LeaseId,
                    row.CanonicalInputJson,
                    row.InputContentHash,
                    MapGovernance(row));
        }
        catch (SqlException exception)
        {
            throw Wrap("read structured explanation input", exception);
        }
    }

    public async Task<bool> RenewLeaseAsync(
        Guid jobPublicId,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("JobPublicId", jobPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("LeaseSeconds", CheckedSeconds(leaseDuration), DbType.Int32);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<LeaseMutationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationJob_RenewLease",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row.Succeeded;
        }
        catch (SqlException exception)
        {
            throw Wrap("renew structured explanation lease", exception);
        }
    }

    public async Task CompleteAsync(
        AiExplanationJobLease lease,
        AiExplanationGeneration generation,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("JobPublicId", lease.JobPublicId, DbType.Guid);
        parameters.Add("LeaseId", lease.LeaseId, DbType.Guid);
        parameters.Add("BudgetReservationPublicId", lease.BudgetReservationPublicId, DbType.Guid);
        parameters.Add("ProviderCode", generation.ProviderCode, DbType.String, size: 50);
        parameters.Add("ModelCode", generation.ModelCode, DbType.String, size: 128);
        parameters.Add("PromptVersion", generation.PromptVersion, DbType.String, size: 50);
        parameters.Add("OutputSchemaVersion", generation.OutputSchemaVersion,
            DbType.String, size: 50);
        parameters.Add("Assessment", (byte)generation.Assessment, DbType.Byte);
        parameters.Add("Summary", generation.Summary, DbType.String, size: 300);
        parameters.Add("PrimaryReasonCode", generation.PrimaryReasonCode,
            DbType.String, size: 64);
        parameters.Add("CitedRuleCodesJson", JsonSerializer.Serialize(generation.CitedRuleCodes),
            DbType.String, size: 1000);
        parameters.Add("OutputFingerprint", generation.OutputFingerprint,
            DbType.Binary, size: 32);
        parameters.Add("ProviderRequestIdHash", generation.ProviderRequestIdHash,
            DbType.Binary, size: 32);
        parameters.Add("InputTokens", generation.InputTokens, DbType.Int32);
        parameters.Add("OutputTokens", generation.OutputTokens, DbType.Int32);
        parameters.Add("EstimatedCostUsd", generation.EstimatedCostUsd,
            DbType.Decimal, precision: 19, scale: 6);
        parameters.Add("LatencyMilliseconds", generation.LatencyMilliseconds, DbType.Int32);
        parameters.Add("CompletedAtUtc", SqlUtc(completedAtUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            _ = await connection.QuerySingleAsync<CompletionMutationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationJob_Complete",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 60,
                    cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw Wrap("complete structured explanation job", exception);
        }
    }

    public async Task FailAsync(
        Guid jobPublicId,
        Guid leaseId,
        string safeCode,
        bool retryable,
        SemanticProviderCallAccounting providerCallAccounting,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("JobPublicId", jobPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("ErrorCode", safeCode, DbType.String, size: 50);
        parameters.Add("Retryable", retryable, DbType.Boolean);
        parameters.Add("ProviderCallMayHaveBeenCharged",
            providerCallAccounting == SemanticProviderCallAccounting.ChargeUncertain,
            DbType.Boolean);
        parameters.Add("FailedAtUtc", SqlUtc(failedAtUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            _ = await connection.QuerySingleAsync<LeaseMutationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_AiExplanationJob_Fail",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw Wrap("fail structured explanation job", exception);
        }
    }

    async Task<(bool Succeeded, string Code, bool WasReplay, AiExplanationRunSummary? Run)>
        IAiExplanationAdministrationRepository.CreateAsync(
            Guid adminUserPublicId,
            Guid sourceSemanticEvaluationRunPublicId,
            string explanationConfigurationVersion,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            bool runtimeEnabled,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("SourceSemanticEvaluationRunPublicId",
            sourceSemanticEvaluationRunPublicId, DbType.Guid);
        parameters.Add("ExplanationConfigurationVersion", explanationConfigurationVersion,
            DbType.String, size: 64);
        parameters.Add("IdempotencyKeyHash", idempotencyKeyHash, DbType.Binary, size: 32);
        parameters.Add("RequestHash", requestHash, DbType.Binary, size: 32);
        parameters.Add("RuntimeEnabled", runtimeEnabled, DbType.Boolean);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<ExplanationMutationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationRun_Create",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 60,
                    cancellationToken: cancellationToken));
            return (row.Succeeded, NormalizeExplanationMutationCode(row.Code), row.WasReplay,
                row.Succeeded ? MapSummary(row) : null);
        }
        catch (SqlException exception)
        {
            throw Wrap("create structured explanation run", exception);
        }
    }

    async Task<AiExplanationRunDetail?> IAiExplanationAdministrationRepository.GetAsync(
        Guid adminUserPublicId,
        Guid runPublicId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("PageNumber", page, DbType.Int32);
        parameters.Add("PageSize", pageSize, DbType.Int32);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_AiExplanationRun_AdminGet",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            var summary = await reader.ReadSingleOrDefaultAsync<ExplanationSummaryRow>();
            if (summary is null) return null;
            var results = (await reader.ReadAsync<ExplanationResultRow>()).ToArray();
            return new AiExplanationRunDetail(
                MapSummary(summary),
                summary.ResultCount,
                summary.PageNumber,
                summary.PageSize,
                results.Select(Map).ToArray());
        }
        catch (SqlException exception)
        {
            throw Wrap("read structured explanation run", exception);
        }
    }

    private static AiExplanationJobLease Map(ExplanationLeaseRow row) => new(
        row.JobPublicId,
        row.LeaseId,
        row.BudgetReservationPublicId,
        row.ExplanationRunPublicId,
        row.ExplanationConfigurationVersion,
        row.ConfigurationFingerprint,
        row.ProviderCode,
        row.ModelCode,
        row.InputSchemaVersion,
        row.OutputSchemaVersion,
        row.PromptVersion,
        row.PromptFingerprint,
        row.ResponseSchemaFingerprint,
        row.MaximumInputUtf8Bytes,
        row.MaximumOutputTokens,
        row.MaximumAttempts,
        row.MaximumCostUsdPerResult,
        row.InputContentHash,
        row.AttemptCount);

    private static AiProviderGovernanceContext MapGovernance(ExplanationInputRow row) => new(
        row.ProviderPolicyPublicId,
        row.ProviderPolicyVersion,
        row.ProviderPolicyFingerprint,
        row.ProviderCapability,
        row.ProviderEndpointOrigin,
        (AiProviderRetentionMode)row.RetentionMode,
        row.MaximumProviderRetentionDays,
        row.DataResidencyCode,
        row.InputTokenCostUsdPerMillion,
        row.OutputTokenCostUsdPerMillion,
        ToUtc(row.ApprovedAtUtc),
        ToUtc(row.ExpiresAtUtc),
        row.ExternalProcessingAllowed);

    private static AiExplanationRunSummary MapSummary(ExplanationSummaryRow row) => new(
        row.PublicId,
        row.SourceSemanticEvaluationRunPublicId,
        (AiExplanationRunStatus)row.Status,
        row.ExplanationConfigurationVersion,
        row.ProviderCode,
        row.ModelCode,
        row.ItemCount,
        row.CompletedCount,
        row.FailedCount,
        row.TotalEstimatedCostUsd,
        ToUtc(row.CreatedAtUtc),
        ToUtc(row.CompletedAtUtc));

    private static AiExplanationResultItem Map(ExplanationResultRow row)
    {
        IReadOnlyList<string> cited;
        try
        {
            cited = JsonSerializer.Deserialize<string[]>(row.CitedRuleCodesJson) ?? [];
        }
        catch (JsonException exception)
        {
            throw new SemanticProcessingDataException(
                "parse structured explanation cited rules", -1, exception);
        }
        return new AiExplanationResultItem(
            row.CaseOrdinal,
            (AiExplanationAssessment)row.Assessment,
            row.Summary,
            row.PrimaryReasonCode,
            cited,
            row.InputTokens,
            row.OutputTokens,
            row.EstimatedCostUsd,
            row.LatencyMilliseconds,
            ToUtc(row.CreatedAtUtc));
    }

    private static string NormalizeExplanationMutationCode(string? code) => code switch
    {
        "created" or "replayed" or "active-run-exists" or
        "budget-insufficient" or "source-or-configuration-not-ready" or
        "structured-outputs-disabled" => code,
        _ => "persistence-unavailable"
    };

    private sealed class ExplanationLeaseRow
    {
        public Guid JobPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public Guid BudgetReservationPublicId { get; init; }
        public Guid ExplanationRunPublicId { get; init; }
        public string ExplanationConfigurationVersion { get; init; } = "";
        public byte[] ConfigurationFingerprint { get; init; } = [];
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public string InputSchemaVersion { get; init; } = "";
        public string OutputSchemaVersion { get; init; } = "";
        public string PromptVersion { get; init; } = "";
        public byte[] PromptFingerprint { get; init; } = [];
        public byte[] ResponseSchemaFingerprint { get; init; } = [];
        public short MaximumInputUtf8Bytes { get; init; }
        public short MaximumOutputTokens { get; init; }
        public byte MaximumAttempts { get; init; }
        public decimal MaximumCostUsdPerResult { get; init; }
        public byte[] InputContentHash { get; init; } = [];
        public byte AttemptCount { get; init; }
    }

    private sealed class ExplanationInputRow
    {
        public Guid JobPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public string CanonicalInputJson { get; init; } = "";
        public byte[] InputContentHash { get; init; } = [];
        public Guid ProviderPolicyPublicId { get; init; }
        public string ProviderPolicyVersion { get; init; } = "";
        public byte[] ProviderPolicyFingerprint { get; init; } = [];
        public byte ProviderCapability { get; init; }
        public string ProviderEndpointOrigin { get; init; } = "";
        public byte RetentionMode { get; init; }
        public short MaximumProviderRetentionDays { get; init; }
        public string DataResidencyCode { get; init; } = "";
        public decimal InputTokenCostUsdPerMillion { get; init; }
        public decimal OutputTokenCostUsdPerMillion { get; init; }
        public DateTime ApprovedAtUtc { get; init; }
        public DateTime ExpiresAtUtc { get; init; }
        public bool ExternalProcessingAllowed { get; init; }
    }

    private class ExplanationSummaryRow
    {
        public Guid PublicId { get; init; }
        public Guid SourceSemanticEvaluationRunPublicId { get; init; }
        public byte Status { get; init; }
        public string ExplanationConfigurationVersion { get; init; } = "";
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public short ItemCount { get; init; }
        public short CompletedCount { get; init; }
        public short FailedCount { get; init; }
        public decimal? TotalEstimatedCostUsd { get; init; }
        public int ResultCount { get; init; }
        public int PageNumber { get; init; }
        public int PageSize { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime? CompletedAtUtc { get; init; }
    }

    private sealed class ExplanationMutationRow : ExplanationSummaryRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public bool WasReplay { get; init; }
    }

    private sealed class ExplanationResultRow
    {
        public int CaseOrdinal { get; init; }
        public byte Assessment { get; init; }
        public string Summary { get; init; } = "";
        public string PrimaryReasonCode { get; init; } = "";
        public string CitedRuleCodesJson { get; init; } = "[]";
        public int InputTokens { get; init; }
        public int OutputTokens { get; init; }
        public decimal EstimatedCostUsd { get; init; }
        public int LatencyMilliseconds { get; init; }
        public DateTime CreatedAtUtc { get; init; }
    }

    private sealed class CompletionMutationRow
    {
        public bool Succeeded { get; init; }
        public bool WasReplay { get; init; }
    }
}
