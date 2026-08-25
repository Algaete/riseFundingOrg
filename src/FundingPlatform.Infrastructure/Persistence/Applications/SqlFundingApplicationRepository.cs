using System.Data;
using Dapper;
using FundingPlatform.Application.Applications;
using FundingPlatform.Core.Applications;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Applications;

public sealed class SqlFundingApplicationRepository(
    ISqlConnectionFactory connectionFactory) : IFundingApplicationRepository
{
    public async Task<FundingApplicationPage> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingApplicationListFilters filters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingApplication_List",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    Status = filters.Status.HasValue ? (byte?)filters.Status.Value : null,
                    filters.ProjectPublicId,
                    filters.FundingOpportunityPublicId,
                    filters.PageNumber,
                    filters.PageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<TotalCountRow>();
            var rows = await reader.ReadAsync<FundingApplicationRow>();
            return new FundingApplicationPage(
                rows.Select(Map).ToArray(),
                metadata.TotalCount,
                filters.PageNumber,
                filters.PageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list applications", exception);
        }
    }

    public async Task<FundingApplicationDetails?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<FundingApplicationRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_FundingApplication_Get",
                    new
                    {
                        UserPublicId = userPublicId,
                        OrganizationPublicId = organizationPublicId,
                        FundingApplicationPublicId = fundingApplicationPublicId
                    },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 15,
                    cancellationToken: cancellationToken));
            return row is null ? null : Map(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("read application", exception);
        }
    }

    public Task<FundingApplicationMutation> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid fundingOpportunityPublicId,
        FundingApplicationData application,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken)
    {
        var parameters = CommonMutationParameters(
            userPublicId,
            organizationPublicId,
            application);
        parameters.Add("ProjectPublicId", projectPublicId);
        parameters.Add("FundingOpportunityPublicId", fundingOpportunityPublicId);
        parameters.Add("IdempotencyKeyHash", idempotencyKeyHash, DbType.Binary, size: 32);
        parameters.Add("RequestHash", requestHash, DbType.Binary, size: 32);
        return MutateAsync(
            "dbo.FundingPlatform_usp_FundingApplication_Create",
            "create application",
            parameters,
            cancellationToken);
    }

    public Task<FundingApplicationMutation> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        byte[] expectedRowVersion,
        FundingApplicationData application,
        CancellationToken cancellationToken)
    {
        var parameters = CommonMutationParameters(
            userPublicId,
            organizationPublicId,
            application);
        parameters.Add("FundingApplicationPublicId", fundingApplicationPublicId);
        parameters.Add("ExpectedRowVersion", expectedRowVersion, DbType.Binary, size: 8);
        parameters.Add("Status", (byte)application.Status);
        return MutateAsync(
            "dbo.FundingPlatform_usp_FundingApplication_Update",
            "update application",
            parameters,
            cancellationToken);
    }

    public async Task<IReadOnlyList<FundingCalendarItem>> ListCalendarAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<FundingCalendarRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationCalendar_List",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    FromDate = from.ToDateTime(TimeOnly.MinValue),
                    ToDate = to.ToDateTime(TimeOnly.MinValue)
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            return rows.Select(Map).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("list calendar", exception);
        }
    }

    private async Task<FundingApplicationMutation> MutateAsync(
        string procedure,
        string operation,
        DynamicParameters parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<FundingApplicationMutationRow>(
                new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
            return new FundingApplicationMutation(
                row.Succeeded,
                row.Code,
                row.FundingApplicationPublicId,
                (FundingApplicationStatus)row.Status,
                row.OwnerUserPublicId,
                row.RowVersion,
                ToUtc(row.CreatedAtUtc),
                ToUtc(row.UpdatedAtUtc),
                row.WasReplay);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static DynamicParameters CommonMutationParameters(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingApplicationData application)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId);
        parameters.Add("OrganizationPublicId", organizationPublicId);
        parameters.Add("Notes", application.Notes);
        parameters.Add("ApplicationDate", application.ApplicationDate.HasValue
            ? application.ApplicationDate.Value.ToDateTime(TimeOnly.MinValue)
            : null);
        parameters.Add("RequestedAmount", application.RequestedAmount);
        parameters.Add("Currency", application.Currency, DbType.AnsiStringFixedLength, size: 3);
        parameters.Add("ResultDate", application.ResultDate.HasValue
            ? application.ResultDate.Value.ToDateTime(TimeOnly.MinValue)
            : null);
        return parameters;
    }

    private static FundingApplicationDetails Map(FundingApplicationRow row) =>
        new(
            row.FundingApplicationPublicId,
            new FundingApplicationReference(
                row.ProjectPublicId,
                row.ProjectSlug,
                row.ProjectTitle),
            new FundingApplicationOpportunityReference(
                row.FundingOpportunityPublicId,
                row.FundingOpportunitySlug,
                row.FundingOpportunityTitle,
                row.SponsorName,
                ToDateOnly(row.CloseDate),
                ToUtc(row.CloseAtUtc),
                row.DeadlinePrecision),
            (FundingApplicationStatus)row.Status,
            row.Notes,
            ToDateOnly(row.ApplicationDate),
            row.RequestedAmount,
            row.Currency?.Trim(),
            ToDateOnly(row.ResultDate),
            row.OwnerUserPublicId,
            row.CanEdit,
            ToUtc(row.CreatedAtUtc),
            ToUtc(row.UpdatedAtUtc),
            row.RowVersion);

    private static FundingCalendarItem Map(FundingCalendarRow row) =>
        new(
            row.EventKey,
            row.EventType,
            DateOnly.FromDateTime(row.EventDate),
            ToUtc(row.EventAtUtc),
            row.DatePrecision,
            row.Title,
            row.Status.HasValue ? (FundingApplicationStatus)row.Status.Value : null,
            row.FundingApplicationPublicId,
            row.ProjectPublicId,
            row.FundingOpportunityPublicId);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static FundingApplicationDataException Wrap(
        string operation,
        SqlException exception) => new(operation, exception.Number, exception);

    private sealed class TotalCountRow
    {
        public long TotalCount { get; init; }
    }

    private sealed class FundingApplicationRow
    {
        public Guid FundingApplicationPublicId { get; init; }
        public byte Status { get; init; }
        public string? Notes { get; init; }
        public DateTime? ApplicationDate { get; init; }
        public decimal? RequestedAmount { get; init; }
        public string? Currency { get; init; }
        public DateTime? ResultDate { get; init; }
        public Guid OwnerUserPublicId { get; init; }
        public bool CanEdit { get; init; }
        public Guid ProjectPublicId { get; init; }
        public string ProjectSlug { get; init; } = "";
        public string ProjectTitle { get; init; } = "";
        public Guid FundingOpportunityPublicId { get; init; }
        public string FundingOpportunitySlug { get; init; } = "";
        public string FundingOpportunityTitle { get; init; } = "";
        public string SponsorName { get; init; } = "";
        public DateTime? CloseDate { get; init; }
        public DateTime? CloseAtUtc { get; init; }
        public byte DeadlinePrecision { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class FundingApplicationMutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public Guid FundingApplicationPublicId { get; init; }
        public byte Status { get; init; }
        public Guid OwnerUserPublicId { get; init; }
        public byte[] RowVersion { get; init; } = [];
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public bool WasReplay { get; init; }
    }

    private sealed class FundingCalendarRow
    {
        public string EventKey { get; init; } = "";
        public string EventType { get; init; } = "";
        public DateTime EventDate { get; init; }
        public DateTime? EventAtUtc { get; init; }
        public byte DatePrecision { get; init; }
        public string Title { get; init; } = "";
        public byte? Status { get; init; }
        public Guid? FundingApplicationPublicId { get; init; }
        public Guid? ProjectPublicId { get; init; }
        public Guid? FundingOpportunityPublicId { get; init; }
    }
}
