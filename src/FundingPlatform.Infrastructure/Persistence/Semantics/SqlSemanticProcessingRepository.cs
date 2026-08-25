using System.Data;
using Dapper;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Core.Semantics;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlTypes;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlSemanticProcessingRepository : ISemanticProcessingRepository
{
    private readonly ISqlConnectionFactory connectionFactory;
    private readonly TimeProvider timeProvider;

    public SqlSemanticProcessingRepository(
        ISqlConnectionFactory connectionFactory,
        TimeProvider timeProvider)
    {
        this.connectionFactory = connectionFactory;
        this.timeProvider = timeProvider;
    }

    public async Task<IReadOnlyList<SemanticEmbeddingJobLease>> ClaimEmbeddingJobsAsync(
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
            var rows = await connection.QueryAsync<EmbeddingLeaseRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return rows.Select(Map).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("claim embedding jobs", exception);
        }
    }

    public async Task<SemanticEmbeddingInput?> GetEmbeddingInputAsync(
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
            var row = await connection.QuerySingleOrDefaultAsync<EmbeddingInputRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_SemanticEmbeddingJob_GetInput",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row is null ? null : new SemanticEmbeddingInput(
                row.JobPublicId,
                row.LeaseId,
                (SemanticSubjectType)row.SubjectType,
                row.SubjectPublicId,
                row.SubjectVersion,
                row.PurposeCode,
                row.CanonicalText,
                row.InputContentHash);
        }
        catch (SqlException exception)
        {
            throw Wrap("read embedding input", exception);
        }
    }

    public async Task<bool> RenewEmbeddingJobLeaseAsync(
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
                    "dbo.FundingPlatform_usp_SemanticEmbeddingJob_RenewLease",
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return row.Succeeded;
        }
        catch (SqlException exception)
        {
            throw Wrap("renew embedding lease", exception);
        }
    }

    public async Task CompleteEmbeddingJobAsync(
        Guid jobPublicId,
        Guid leaseId,
        Guid budgetReservationPublicId,
        SemanticEmbeddingGeneration generation,
        DateTimeOffset completedAtUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        await using var command = connection.CreateCommand();
        command.CommandText = "dbo.FundingPlatform_usp_SemanticEmbeddingJob_Complete";
        command.CommandType = CommandType.StoredProcedure;
        command.CommandTimeout = 60;
        command.Parameters.Add("JobPublicId", SqlDbType.UniqueIdentifier).Value = jobPublicId;
        command.Parameters.Add("LeaseId", SqlDbType.UniqueIdentifier).Value = leaseId;
        command.Parameters.Add("BudgetReservationPublicId", SqlDbType.UniqueIdentifier).Value =
            budgetReservationPublicId;
        command.Parameters.Add("ProviderCode", SqlDbType.NVarChar, 50).Value =
            generation.ProviderCode;
        command.Parameters.Add("ModelCode", SqlDbType.NVarChar, 128).Value =
            generation.ModelCode;
        command.Parameters.Add("TemplateVersion", SqlDbType.NVarChar, 50).Value =
            generation.TemplateVersion;
        command.Parameters.Add(new SqlParameter(
            "Embedding",
            Microsoft.Data.SqlDbTypeExtensions.Vector)
        {
            Value = new SqlVector<float>(generation.Vector.AsMemory())
        });
        AddNullableInt(command, "InputTokens", generation.InputTokens);
        AddNullableInt(command, "OutputTokens", generation.OutputTokens);
        var cost = command.Parameters.Add("EstimatedCostUsd", SqlDbType.Decimal);
        cost.Precision = 19;
        cost.Scale = 6;
        cost.Value = generation.EstimatedCostUsd;
        command.Parameters.Add("ProviderRequestIdHash", SqlDbType.Binary, 32).Value =
            generation.ProviderRequestIdHash is null
                ? DBNull.Value
                : generation.ProviderRequestIdHash;
        command.Parameters.Add("LatencyMilliseconds", SqlDbType.Int).Value =
            generation.LatencyMilliseconds;
        AddDateTime2(command, "CompletedAtUtc", completedAtUtc);

        try
        {
            await connection.OpenAsync(cancellationToken);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }
        catch (SqlException exception)
        {
            throw Wrap("complete embedding job", exception);
        }
    }

    public async Task FailEmbeddingJobAsync(
        Guid jobPublicId,
        Guid leaseId,
        string errorCode,
        bool retryable,
        SemanticProviderCallAccounting providerCallAccounting,
        DateTimeOffset failedAtUtc,
        CancellationToken cancellationToken)
    {
        var mayHaveBeenCharged = providerCallAccounting switch
        {
            SemanticProviderCallAccounting.NotInvoked => false,
            SemanticProviderCallAccounting.ChargeUncertain => true,
            _ => throw new ArgumentOutOfRangeException(nameof(providerCallAccounting))
        };
        var parameters = new DynamicParameters();
        parameters.Add("JobPublicId", jobPublicId, DbType.Guid);
        parameters.Add("LeaseId", leaseId, DbType.Guid);
        parameters.Add("ErrorCode", errorCode, DbType.String, size: 50);
        parameters.Add("Retryable", retryable, DbType.Boolean);
        parameters.Add("ProviderCallMayHaveBeenCharged", mayHaveBeenCharged, DbType.Boolean);
        parameters.Add("FailedAtUtc", SqlUtc(failedAtUtc), DbType.DateTime2);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            await connection.ExecuteAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticEmbeddingJob_Fail",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw Wrap("fail embedding job", exception);
        }
    }

    private static SemanticEmbeddingJobLease Map(EmbeddingLeaseRow row) => new(
        row.JobPublicId,
        row.LeaseId,
        row.BudgetReservationPublicId,
        (SemanticSubjectType)row.SubjectType,
        row.SubjectPublicId,
        row.SubjectVersion,
        row.SemanticConfigurationVersion,
        row.SemanticConfigurationFingerprint,
        row.ProviderCode,
        row.ModelCode,
        row.Dimensions,
        row.PurposeCode,
        row.TemplateVersion,
        row.NormalizationVersion,
        row.MaximumInputUtf8Bytes,
        row.MaximumBatchSize,
        row.MaximumAttempts,
        row.MaximumCostUsdPerEmbedding,
        row.InputContentHash,
        row.AttemptCount);

    private static int CheckedSeconds(TimeSpan value) => checked((int)value.TotalSeconds);

    private static DateTime SqlUtc(DateTimeOffset value) => value.UtcDateTime;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static void AddDateTime2(
        SqlCommand command,
        string name,
        DateTimeOffset value)
    {
        var parameter = command.Parameters.Add(name, SqlDbType.DateTime2);
        parameter.Scale = 3;
        parameter.Value = SqlUtc(value);
    }

    private static void AddNullableInt(SqlCommand command, string name, int? value) =>
        command.Parameters.Add(name, SqlDbType.Int).Value = value ?? (object)DBNull.Value;

    private static SemanticProcessingDataException Wrap(
        string operation,
        SqlException exception) => new(operation, exception.Number, exception);

    private sealed class EmbeddingLeaseRow
    {
        public Guid JobPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public Guid BudgetReservationPublicId { get; init; }
        public byte SubjectType { get; init; }
        public Guid SubjectPublicId { get; init; }
        public int SubjectVersion { get; init; }
        public string SemanticConfigurationVersion { get; init; } = "";
        public byte[] SemanticConfigurationFingerprint { get; init; } = [];
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public int Dimensions { get; init; }
        public string PurposeCode { get; init; } = "";
        public string TemplateVersion { get; init; } = "";
        public string NormalizationVersion { get; init; } = "";
        public short MaximumInputUtf8Bytes { get; init; }
        public byte MaximumBatchSize { get; init; }
        public byte MaximumAttempts { get; init; }
        public decimal MaximumCostUsdPerEmbedding { get; init; }
        public byte[] InputContentHash { get; init; } = [];
        public short AttemptCount { get; init; }
    }

    private sealed class EmbeddingInputRow
    {
        public Guid JobPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public byte SubjectType { get; init; }
        public Guid SubjectPublicId { get; init; }
        public int SubjectVersion { get; init; }
        public string PurposeCode { get; init; } = "";
        public string CanonicalText { get; init; } = "";
        public byte[] InputContentHash { get; init; } = [];
    }

    private sealed class LeaseMutationRow
    {
        public bool Succeeded { get; init; }
    }
}
