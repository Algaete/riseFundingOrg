using System.Data;
using Dapper;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlAiProviderGovernanceAdministrationRepository(
    ISqlConnectionFactory connectionFactory) : IAiProviderGovernanceAdministrationRepository
{
    public async Task<AiEmbeddingProviderPolicyMutation> RegisterEmbeddingPolicyAsync(
        AiEmbeddingProviderPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<PolicyRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_AiEmbeddingProviderPolicy_AdminRegister",
                new
                {
                    command.SuperAdminUserPublicId,
                    command.Code,
                    command.Version,
                    command.ModelCode,
                    command.EndpointOrigin,
                    command.DataResidencyCode,
                    command.DpaReferenceHash,
                    command.TermsSnapshotHash,
                    command.InputTokenCostUsdPerMillion,
                    ApprovedAtUtc = command.ApprovedAtUtc.UtcDateTime,
                    ExpiresAtUtc = command.ExpiresAtUtc.UtcDateTime,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new AiEmbeddingProviderPolicyMutation(
                row.Succeeded, row.Code, row.WasReplay, row.PublicId, row.PolicyVersion,
                row.ProviderCode, row.ModelCode, row.EndpointOrigin, row.RetentionMode,
                row.MaximumProviderRetentionDays, row.DataResidencyCode,
                row.PolicyFingerprint, row.InputTokenCostUsdPerMillion,
                row.ExternalProcessingAllowed, row.IsActive,
                new DateTimeOffset(DateTime.SpecifyKind(row.ApprovedAtUtc, DateTimeKind.Utc)),
                new DateTimeOffset(DateTime.SpecifyKind(row.ExpiresAtUtc, DateTimeKind.Utc)));
        }
        catch (SqlException exception)
        {
            throw new AiProviderGovernanceAdministrationDataException(
                "register governed embedding provider policy", exception.Number, exception);
        }
    }

    public async Task<OpenAiSemanticConfigurationMutation> PublishOpenAiConfigurationAsync(
        OpenAiSemanticConfigurationCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<ConfigurationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SemanticConfiguration_AdminPublishOpenAi",
                new
                {
                    command.SuperAdminUserPublicId,
                    command.ProviderPolicyPublicId,
                    command.Code,
                    command.Version,
                    command.MaximumBatchSize,
                    command.MaximumCostUsdPerEmbedding,
                    command.MonthlyBudgetUsd,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new OpenAiSemanticConfigurationMutation(
                row.Succeeded, row.Code, row.WasReplay, row.PublicId,
                row.ConfigurationVersion, row.ProviderPolicyPublicId,
                row.ProviderPolicyFingerprint, row.ProviderCode, row.ModelCode,
                row.Dimensions, row.MaximumBatchSize,
                row.MaximumCostUsdPerEmbedding, row.MonthlyBudgetUsd,
                row.IsActive,
                new DateTimeOffset(DateTime.SpecifyKind(row.PublishedAtUtc, DateTimeKind.Utc)));
        }
        catch (SqlException exception)
        {
            throw new AiProviderGovernanceAdministrationDataException(
                "publish governed OpenAI semantic configuration", exception.Number, exception);
        }
    }

    private sealed class PolicyRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public bool WasReplay { get; init; }
        public Guid PublicId { get; init; }
        public string PolicyVersion { get; init; } = string.Empty;
        public string ProviderCode { get; init; } = string.Empty;
        public string ModelCode { get; init; } = string.Empty;
        public string EndpointOrigin { get; init; } = string.Empty;
        public byte RetentionMode { get; init; }
        public short MaximumProviderRetentionDays { get; init; }
        public string DataResidencyCode { get; init; } = string.Empty;
        public byte[] PolicyFingerprint { get; init; } = [];
        public decimal InputTokenCostUsdPerMillion { get; init; }
        public bool ExternalProcessingAllowed { get; init; }
        public bool IsActive { get; init; }
        public DateTime ApprovedAtUtc { get; init; }
        public DateTime ExpiresAtUtc { get; init; }
    }

    private sealed class ConfigurationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public bool WasReplay { get; init; }
        public Guid PublicId { get; init; }
        public string ConfigurationVersion { get; init; } = string.Empty;
        public Guid ProviderPolicyPublicId { get; init; }
        public byte[] ProviderPolicyFingerprint { get; init; } = [];
        public string ProviderCode { get; init; } = string.Empty;
        public string ModelCode { get; init; } = string.Empty;
        public short Dimensions { get; init; }
        public byte MaximumBatchSize { get; init; }
        public decimal MaximumCostUsdPerEmbedding { get; init; }
        public decimal MonthlyBudgetUsd { get; init; }
        public bool IsActive { get; init; }
        public DateTime PublishedAtUtc { get; init; }
    }
}
