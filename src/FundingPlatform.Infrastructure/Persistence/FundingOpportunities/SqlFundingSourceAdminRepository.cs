using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingSourceAdminRepository(
    ISqlConnectionFactory connectionFactory) : IFundingSourceAdminRepository
{
    public async Task<IReadOnlyList<FundingSourceAdminOption>> ListAsync(
        Guid adminUserPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<FundingSourceAdminRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingSource_AdminList",
                new { AdminUserPublicId = adminUserPublicId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return rows.Select(row => new FundingSourceAdminOption(
                row.Id,
                row.Name,
                row.ProviderType,
                row.BaseUrl,
                row.IsEnabled,
                row.ProviderCode,
                row.ComplianceStatus,
                ToUtc(row.NextRunAtUtc),
                ToUtc(row.LastSuccessfulRunAtUtc),
                row.LicenseStatus,
                row.LicenseName,
                row.LicenseUrl,
                ToUtc(row.LicenseReviewedAtUtc),
                ToUtc(row.LicenseExpiresAtUtc),
                row.RobotsPolicyStatus,
                ToUtc(row.RobotsReviewedAtUtc),
                ToUtc(row.RobotsExpiresAtUtc),
                row.RequestRateLimitPerMinute,
                row.MaximumResponseBytes,
                row.ContentRetentionDays,
                row.AllowedHostsRequired,
                row.AcquisitionPolicyVersion,
                row.EnabledAllowedHostCount,
                row.AcquisitionReady)).ToArray();
        }
        catch (SqlException exception)
        {
            throw new FundingEditorialDataException(
                "list funding sources for administration", exception.Number, exception);
        }
    }

    private static DateTimeOffset? ToUtc(DateTime? value) => value.HasValue
        ? new DateTimeOffset(DateTime.SpecifyKind(value.Value, DateTimeKind.Utc))
        : null;

    private sealed class FundingSourceAdminRow
    {
        public int Id { get; init; }
        public string Name { get; init; } = string.Empty;
        public byte ProviderType { get; init; }
        public string? BaseUrl { get; init; }
        public bool IsEnabled { get; init; }
        public string? ProviderCode { get; init; }
        public string ComplianceStatus { get; init; } = "pending";
        public byte LicenseStatus { get; init; }
        public string? LicenseName { get; init; }
        public string? LicenseUrl { get; init; }
        public DateTime? LicenseReviewedAtUtc { get; init; }
        public DateTime? LicenseExpiresAtUtc { get; init; }
        public byte RobotsPolicyStatus { get; init; }
        public DateTime? RobotsReviewedAtUtc { get; init; }
        public DateTime? RobotsExpiresAtUtc { get; init; }
        public int? RequestRateLimitPerMinute { get; init; }
        public int? MaximumResponseBytes { get; init; }
        public short? ContentRetentionDays { get; init; }
        public bool AllowedHostsRequired { get; init; }
        public int AcquisitionPolicyVersion { get; init; }
        public int EnabledAllowedHostCount { get; init; }
        public bool AcquisitionReady { get; init; }
        public DateTime? NextRunAtUtc { get; init; }
        public DateTime? LastSuccessfulRunAtUtc { get; init; }
    }
}
