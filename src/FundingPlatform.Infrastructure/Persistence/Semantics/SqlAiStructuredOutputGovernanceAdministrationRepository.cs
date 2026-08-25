using System.Data;
using Dapper;
using FundingPlatform.Application.Semantics;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Semantics;

public sealed partial class SqlAiProviderGovernanceAdministrationRepository
{
    public async Task<AiStructuredOutputProviderPolicyMutation>
        RegisterStructuredOutputPolicyAsync(
            AiStructuredOutputProviderPolicyCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<StructuredPolicyRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiStructuredOutputProviderPolicy_AdminRegister",
                    new
                    {
                        command.SuperAdminUserPublicId,
                        command.Code,
                        command.Version,
                        command.EndpointOrigin,
                        command.DataResidencyCode,
                        command.DpaReferenceHash,
                        command.TermsSnapshotHash,
                        command.InputTokenCostUsdPerMillion,
                        command.OutputTokenCostUsdPerMillion,
                        ApprovedAtUtc = command.ApprovedAtUtc.UtcDateTime,
                        ExpiresAtUtc = command.ExpiresAtUtc.UtcDateTime,
                        IdempotencyKeyHash = idempotencyKeyHash,
                        RequestHash = requestHash,
                        NowUtc = nowUtc.UtcDateTime
                    },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return new AiStructuredOutputProviderPolicyMutation(
                row.Succeeded, row.Code, row.WasReplay, row.PublicId,
                row.PolicyVersion, row.ProviderCode, row.ModelCode, row.Capability,
                row.EndpointOrigin, row.RetentionMode, row.MaximumProviderRetentionDays,
                row.DataResidencyCode, row.PolicyFingerprint,
                row.InputTokenCostUsdPerMillion, row.OutputTokenCostUsdPerMillion,
                row.ExternalProcessingAllowed, row.IsActive,
                Utc(row.ApprovedAtUtc), Utc(row.ExpiresAtUtc));
        }
        catch (SqlException exception)
        {
            throw new AiProviderGovernanceAdministrationDataException(
                "register governed Structured Outputs provider policy",
                exception.Number,
                exception);
        }
    }

    public async Task<OpenAiExplanationConfigurationMutation>
        PublishOpenAiExplanationConfigurationAsync(
            OpenAiExplanationConfigurationCommand command,
            byte[] idempotencyKeyHash,
            byte[] requestHash,
            DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<ExplanationConfigurationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AiExplanationConfiguration_AdminPublishOpenAi",
                    new
                    {
                        command.SuperAdminUserPublicId,
                        command.ProviderPolicyPublicId,
                        command.Code,
                        command.Version,
                        command.MaximumOutputTokens,
                        command.MaximumCostUsdPerResult,
                        command.MonthlyBudgetUsd,
                        IdempotencyKeyHash = idempotencyKeyHash,
                        RequestHash = requestHash,
                        NowUtc = nowUtc.UtcDateTime
                    },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return new OpenAiExplanationConfigurationMutation(
                row.Succeeded, row.Code, row.WasReplay, row.PublicId,
                row.ConfigurationVersion, row.ProviderPolicyPublicId,
                row.ProviderPolicyFingerprint, row.ProviderCode, row.ModelCode,
                row.InputSchemaVersion, row.OutputSchemaVersion, row.PromptVersion,
                row.PromptFingerprint, row.ResponseSchemaFingerprint,
                row.MaximumOutputTokens, row.MaximumCostUsdPerResult,
                row.MonthlyBudgetUsd, row.IsActive, Utc(row.PublishedAtUtc));
        }
        catch (SqlException exception)
        {
            throw new AiProviderGovernanceAdministrationDataException(
                "publish governed OpenAI explanation configuration",
                exception.Number,
                exception);
        }
    }

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private sealed class StructuredPolicyRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public bool WasReplay { get; init; }
        public Guid PublicId { get; init; }
        public string PolicyVersion { get; init; } = "";
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public byte Capability { get; init; }
        public string EndpointOrigin { get; init; } = "";
        public byte RetentionMode { get; init; }
        public short MaximumProviderRetentionDays { get; init; }
        public string DataResidencyCode { get; init; } = "";
        public byte[] PolicyFingerprint { get; init; } = [];
        public decimal InputTokenCostUsdPerMillion { get; init; }
        public decimal OutputTokenCostUsdPerMillion { get; init; }
        public bool ExternalProcessingAllowed { get; init; }
        public bool IsActive { get; init; }
        public DateTime ApprovedAtUtc { get; init; }
        public DateTime ExpiresAtUtc { get; init; }
    }

    private sealed class ExplanationConfigurationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public bool WasReplay { get; init; }
        public Guid PublicId { get; init; }
        public string ConfigurationVersion { get; init; } = "";
        public Guid ProviderPolicyPublicId { get; init; }
        public byte[] ProviderPolicyFingerprint { get; init; } = [];
        public string ProviderCode { get; init; } = "";
        public string ModelCode { get; init; } = "";
        public string InputSchemaVersion { get; init; } = "";
        public string OutputSchemaVersion { get; init; } = "";
        public string PromptVersion { get; init; } = "";
        public byte[] PromptFingerprint { get; init; } = [];
        public byte[] ResponseSchemaFingerprint { get; init; } = [];
        public short MaximumOutputTokens { get; init; }
        public decimal MaximumCostUsdPerResult { get; init; }
        public decimal MonthlyBudgetUsd { get; init; }
        public bool IsActive { get; init; }
        public DateTime PublishedAtUtc { get; init; }
    }
}
