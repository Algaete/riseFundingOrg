using System.Data;
using Dapper;
using FundingPlatform.Core.Semantics;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlSemanticProcessingRepository
{
    public async Task<IReadOnlyList<SemanticShadowEvaluationRunLease>>
        ClaimShadowEvaluationRunsAsync(
            string workerInstanceId,
            int batchSize,
            TimeSpan leaseDuration,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("WorkerInstanceId", workerInstanceId, DbType.String, size: 128);
        parameters.Add("BatchSize", batchSize, DbType.Int32);
        parameters.Add("LeaseSeconds", CheckedSeconds(leaseDuration), DbType.Int32);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<EvaluationLeaseRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEvaluationRun_Claim",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(row => new SemanticShadowEvaluationRunLease(
                row.RunPublicId,
                row.LeaseId,
                row.SemanticConfigurationVersion,
                row.SemanticConfigurationFingerprint,
                row.ProviderCode,
                row.ModelCode,
                row.PurposeCode,
                row.NormalizationVersion,
                row.ProjectTemplateVersion,
                row.OpportunityTemplateVersion,
                row.CalibrationVersion,
                row.DistanceMetric,
                row.MaximumAttempts,
                row.Dimensions,
                row.PairCount,
                row.AttemptCount)).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("claim semantic evaluation runs", exception);
        }
    }

    public async Task<bool> RenewShadowEvaluationRunLeaseAsync(
        Guid runPublicId,
        Guid leaseId,
        TimeSpan leaseDuration,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("LeaseSeconds", CheckedSeconds(leaseDuration), DbType.Int32);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        return await ReadMutationAsync(
            "dbo.FundingPlatform_usp_SemanticEvaluationRun_RenewLease",
            "renew semantic evaluation lease",
            parameters,
            cancellationToken);
    }

    public async Task<SemanticShadowEvaluationWorkState?> GetShadowEvaluationWorkStateAsync(
        Guid runPublicId,
        Guid leaseId,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<EvaluationWorkRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_SemanticEvaluationRun_GetWork",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row is null ? null : new SemanticShadowEvaluationWorkState(
                row.RunPublicId,
                row.LeaseId,
                row.PairCount,
                checked((int)row.ReadyPairCount),
                checked((int)row.PendingEmbeddingJobCount),
                checked((int)row.PermanentFailedEmbeddingJobCount));
        }
        catch (SqlException exception)
        {
            throw Wrap("read semantic evaluation work", exception);
        }
    }

    public async Task CompleteShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("CompletedAtUtc", SqlUtc(completedAtUtc), DbType.DateTime2);
        await ExecuteAsync(
            "dbo.FundingPlatform_usp_SemanticEvaluationRun_Complete",
            "complete semantic evaluation run",
            parameters,
            120,
            cancellationToken);
    }

    public async Task ReleaseShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        string reasonCode,
        DateTimeOffset nextAttemptAtUtc,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("ReasonCode", reasonCode, DbType.String, size: 50);
        parameters.Add("NextAttemptAtUtc", SqlUtc(nextAttemptAtUtc), DbType.DateTime2);
        parameters.Add("NowUtc", SqlUtc(nowUtc), DbType.DateTime2);
        _ = await ReadMutationAsync(
            "dbo.FundingPlatform_usp_SemanticEvaluationRun_Wait",
            "defer semantic evaluation run",
            parameters,
            cancellationToken);
    }

    public async Task FailShadowEvaluationRunAsync(
        Guid runPublicId,
        Guid leaseId,
        string errorCode,
        bool retryable,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("RunPublicId", runPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("ErrorCode", errorCode, DbType.String, size: 50);
        parameters.Add("Retryable", retryable, DbType.Boolean);
        parameters.Add("FailedAtUtc", SqlUtc(failedAtUtc), DbType.DateTime2);
        _ = await ReadMutationAsync(
            "dbo.FundingPlatform_usp_SemanticEvaluationRun_Fail",
            "fail semantic evaluation run",
            parameters,
            cancellationToken);
    }

    private async Task<bool> ReadMutationAsync(
        string procedure,
        string operation,
        DynamicParameters parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<LeaseMutationRow>(
                new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row.Succeeded;
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private async Task ExecuteAsync(
        string procedure,
        string operation,
        DynamicParameters parameters,
        int commandTimeout,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: commandTimeout,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private sealed class EvaluationLeaseRow
    {
        public Guid RunPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public string SemanticConfigurationVersion { get; init; } = "";
        public byte[] SemanticConfigurationFingerprint { get; init; } = [];
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public string PurposeCode { get; init; } = "";
        public string NormalizationVersion { get; init; } = "";
        public string ProjectTemplateVersion { get; init; } = "";
        public string OpportunityTemplateVersion { get; init; } = "";
        public string CalibrationVersion { get; init; } = "";
        public byte DistanceMetric { get; init; }
        public byte MaximumAttempts { get; init; }
        public int Dimensions { get; init; }
        public int PairCount { get; init; }
        public short AttemptCount { get; init; }
    }

    private sealed class EvaluationWorkRow
    {
        public Guid RunPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public int PairCount { get; init; }
        public long ReadyPairCount { get; init; }
        public long PendingEmbeddingJobCount { get; init; }
        public long PermanentFailedEmbeddingJobCount { get; init; }
    }
}
