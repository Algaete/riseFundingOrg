using System.Data;
using Dapper;
using FundingPlatform.Application.Administration;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Administration;

public sealed class SqlAdminOperationsRepository(
    ISqlConnectionFactory connectionFactory) : IAdminOperationsRepository
{
    public async Task<AdminOrganizationPage> ListOrganizationsAsync(
        Guid adminUserPublicId,
        AdminOrganizationQuery query,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = connectionFactory.CreateConnection();
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_AdminOrganization_List",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    Query = Normalize(query.Search),
                    query.ProfileStatus,
                    query.IsActive,
                    PageNumber = query.Page,
                    query.PageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var total = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<OrganizationSummaryRow>()).ToArray();
            return new AdminOrganizationPage(rows.Select(Map).ToArray(), total,
                query.Page, query.PageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list-organizations", exception);
        }
    }

    public async Task<AdminOrganizationDetail?> GetOrganizationAsync(
        Guid adminUserPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = connectionFactory.CreateConnection();
            var row = await connection.QuerySingleOrDefaultAsync<OrganizationDetailRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_AdminOrganization_Get",
                    new { AdminUserPublicId = adminUserPublicId, OrganizationPublicId = organizationPublicId },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 20,
                    cancellationToken: cancellationToken));
            return row is null ? null : Map(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("get-organization", exception);
        }
    }

    public async Task<AdminOperationalErrorPage> ListOperationalErrorsAsync(
        Guid adminUserPublicId,
        AdminOperationalErrorQuery query,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = connectionFactory.CreateConnection();
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_AdminOperationalError_List",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    Query = Normalize(query.Search),
                    query.Category,
                    query.Retryable,
                    PageNumber = query.Page,
                    query.PageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var total = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<OperationalErrorRow>()).ToArray();
            return new AdminOperationalErrorPage(rows.Select(Map).ToArray(), total,
                query.Page, query.PageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list-operational-errors", exception);
        }
    }

    private static string? Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static AdminOperationsDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private static AdminOrganizationSummary Map(OrganizationSummaryRow row) => new(
        row.OrganizationPublicId, row.OrganizationName, row.CountryCode, row.CountryName,
        row.OrganizationTypeName, row.ProfileStatus, row.ProfileCompleteness, row.IsActive,
        row.MemberCount, row.ProjectCount, row.PlanCode, row.PlanName,
        row.SubscriptionStatus, Utc(row.CreatedAtUtc), Utc(row.UpdatedAtUtc));

    private static AdminOrganizationDetail Map(OrganizationDetailRow row) => new(
        row.OrganizationPublicId, row.OrganizationName, row.LegalName, row.CountryCode,
        row.CountryName, row.OrganizationTypeName, row.LegalEntityTypeName,
        row.OrganizationSizeName, row.EstablishedYear, row.WebsiteUrl, row.Description,
        row.ProfileStatus, row.ProfileCompleteness, row.ProfileVersion, row.IsActive,
        row.MemberCount, row.AdminMemberCount, row.ProjectCount, row.PublishedProjectCount,
        row.PlanCode, row.PlanName, row.SubscriptionStatus, Utc(row.CurrentPeriodEndUtc),
        Utc(row.CreatedAtUtc), Utc(row.UpdatedAtUtc));

    private static AdminOperationalErrorItem Map(OperationalErrorRow row) => new(
        row.EventId, row.Category, row.Severity, row.ErrorCode, row.SanitizedMessage,
        row.IsRetryable, Utc(row.OccurredAtUtc), row.RelatedResourcePublicId, row.SourceName);

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? Utc(DateTime? value) =>
        value is null ? null : Utc(value.Value);

    private class OrganizationSummaryRow
    {
        public Guid OrganizationPublicId { get; init; }
        public string OrganizationName { get; init; } = string.Empty;
        public string CountryCode { get; init; } = string.Empty;
        public string CountryName { get; init; } = string.Empty;
        public string OrganizationTypeName { get; init; } = string.Empty;
        public byte ProfileStatus { get; init; }
        public decimal ProfileCompleteness { get; init; }
        public bool IsActive { get; init; }
        public long MemberCount { get; init; }
        public long ProjectCount { get; init; }
        public string PlanCode { get; init; } = string.Empty;
        public string PlanName { get; init; } = string.Empty;
        public byte? SubscriptionStatus { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
    }

    private sealed class OrganizationDetailRow : OrganizationSummaryRow
    {
        public string? LegalName { get; init; }
        public string? LegalEntityTypeName { get; init; }
        public string? OrganizationSizeName { get; init; }
        public int? EstablishedYear { get; init; }
        public string? WebsiteUrl { get; init; }
        public string? Description { get; init; }
        public int ProfileVersion { get; init; }
        public long AdminMemberCount { get; init; }
        public long PublishedProjectCount { get; init; }
        public DateTime? CurrentPeriodEndUtc { get; init; }
    }

    private sealed class OperationalErrorRow
    {
        public string EventId { get; init; } = string.Empty;
        public string Category { get; init; } = string.Empty;
        public byte Severity { get; init; }
        public string ErrorCode { get; init; } = string.Empty;
        public string SanitizedMessage { get; init; } = string.Empty;
        public bool IsRetryable { get; init; }
        public DateTime OccurredAtUtc { get; init; }
        public Guid? RelatedResourcePublicId { get; init; }
        public string? SourceName { get; init; }
    }
}
