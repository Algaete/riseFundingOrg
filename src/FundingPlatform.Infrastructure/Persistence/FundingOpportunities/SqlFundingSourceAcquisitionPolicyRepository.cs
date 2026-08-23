using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingSourceAcquisitionPolicyRepository(
    ISqlConnectionFactory connectionFactory) : IFundingSourceAcquisitionPolicyRepository
{
    public async Task<FundingSourceAcquisitionPolicyMutation> UpsertAsync(
        FundingSourceAcquisitionPolicyCommand command,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        var hostsJson = JsonSerializer.Serialize(command.AllowedHosts);
        var endpointsJson = JsonSerializer.Serialize(command.AllowedEndpoints.Select(
            static endpoint => new
            {
                kind = (byte)endpoint.Kind,
                uri = endpoint.CanonicalUri
            }));
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<Row>(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingSourceAcquisitionPolicy_Upsert",
                new
                {
                    SuperAdminUserPublicId = command.SuperAdminUserId,
                    command.ProviderCode,
                    command.BaseUrl,
                    command.LicenseName,
                    command.LicenseUrl,
                    LicenseReviewedAtUtc = command.LicenseReviewedAtUtc.UtcDateTime,
                    LicenseExpiresAtUtc = command.LicenseExpiresAtUtc?.UtcDateTime,
                    command.RobotsPolicyCode,
                    command.RobotsPolicyVersion,
                    RobotsReviewedAtUtc = command.RobotsReviewedAtUtc.UtcDateTime,
                    RobotsExpiresAtUtc = command.RobotsExpiresAtUtc?.UtcDateTime,
                    AllowedHostsJson = hostsJson,
                    AllowedEndpointsJson = endpointsJson,
                    command.RequestRateLimitPerMinute,
                    command.MaximumResponseBytes,
                    command.ContentRetentionDays,
                    command.ScheduleIntervalSeconds,
                    command.IsEnabled,
                    command.ComplianceApproved,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    command.CorrelationId,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return new FundingSourceAcquisitionPolicyMutation(
                row.Succeeded,
                row.Code,
                row.FundingSourceId,
                row.PolicyPublicId,
                row.PolicyVersion,
                row.AcquisitionPolicyFingerprint,
                row.IsEnabled,
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw new FundingSourceAcquisitionPolicyDataException(
                "configure funding-source acquisition policy",
                exception.Number,
                exception);
        }
    }

    private sealed class Row
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public int? FundingSourceId { get; init; }
        public Guid? PolicyPublicId { get; init; }
        public int? PolicyVersion { get; init; }
        public byte[]? AcquisitionPolicyFingerprint { get; init; }
        public bool? IsEnabled { get; init; }
        public bool WasReplay { get; init; }
    }
}
