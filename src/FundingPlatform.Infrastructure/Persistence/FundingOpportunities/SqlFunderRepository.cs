using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFunderRepository(
    ISqlConnectionFactory connectionFactory) : IFunderRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<FunderPage> ListAdminAsync(
        Guid adminUserPublicId,
        string? query,
        FundingPublicationStatus? publicationStatus,
        bool includeInactive,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Funder_Admin_List",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    Query = query,
                    PublicationStatus = publicationStatus.HasValue
                        ? (byte?)publicationStatus.Value
                        : null,
                    IncludeInactive = includeInactive,
                    PageNumber = pageNumber,
                    PageSize = pageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<FunderRow>()).AsList();
            return new FunderPage(rows.Select(MapSummary).ToArray(), totalCount, pageNumber, pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list funders for administration", exception);
        }
    }

    public async Task<FunderDetails?> GetAdminAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Funder_Admin_Get",
                new
                {
                    AdminUserPublicId = adminUserPublicId,
                    FunderPublicId = funderPublicId
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<FunderRow>();
            if (row is null)
            {
                return null;
            }

            var aliases = (await reader.ReadAsync<FunderAliasRow>())
                .Where(alias => alias.IsActive && !alias.IsPrimary)
                .Select(alias => alias.Alias)
                .ToArray();
            var opportunities = (await reader.ReadAsync<FunderOpportunityRow>())
                .Select(item => new FunderOpportunitySummary(
                    item.FundingOpportunityPublicId,
                    item.Slug,
                    item.Title,
                    (FunderOpportunityRole)item.Role,
                    (FundingPublicationStatus)item.PublicationStatus,
                    item.IsActive))
                .ToArray();
            return MapDetails(row, aliases, opportunities);
        }
        catch (SqlException exception) when (exception.Number == 51606)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read funder for administration", exception);
        }
    }

    public Task<FundingEditorialMutation> CreateAsync(
        Guid adminUserPublicId,
        string slug,
        FunderData data,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteCommandAsync(
        "dbo.FundingPlatform_usp_Funder_Create",
        "create funder",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            Slug = slug,
            data.Name,
            data.Description,
            data.WebsiteUrl,
            data.CountryId,
            AliasesJson = SerializeAliases(data.Aliases),
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        cancellationToken);

    public Task<FundingEditorialMutation> UpdateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        FunderData data,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteCommandAsync(
        "dbo.FundingPlatform_usp_Funder_Update",
        "update funder",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FunderPublicId = funderPublicId,
            ExpectedRowVersion = expectedRowVersion,
            data.Name,
            data.Description,
            data.WebsiteUrl,
            data.CountryId,
            AliasesJson = SerializeAliases(data.Aliases),
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        cancellationToken);

    public Task<FundingEditorialMutation> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_Funder_RequestPublication",
        "request funder publication",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FunderPublicId = funderPublicId,
            ExpectedRowVersion = expectedRowVersion,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: true,
        cancellationToken);

    public Task<FundingEditorialMutation> ReviewAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        FundingReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_Funder_AdminReview",
        "review funder",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FunderPublicId = funderPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Decision = (byte)decision,
            RejectionReason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    public Task<FundingEditorialMutation> DeactivateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string? reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_Funder_Deactivate",
        "deactivate funder",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FunderPublicId = funderPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Reason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    public Task<FundingEditorialMutation> StartCorrectionAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string reason,
        byte[] expectedRowVersion,
        byte[] idempotencyKeyHash,
        byte[] requestHash,
        CancellationToken cancellationToken) => ExecuteWorkflowAsync(
        "dbo.FundingPlatform_usp_Funder_StartCorrection",
        "start funder correction",
        new
        {
            AdminUserPublicId = adminUserPublicId,
            FunderPublicId = funderPublicId,
            ExpectedRowVersion = expectedRowVersion,
            Reason = reason,
            IdempotencyKeyHash = idempotencyKeyHash,
            RequestHash = requestHash
        },
        readsIssues: false,
        cancellationToken);

    public async Task<PublicFunderPage> ListPublishedAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Funder_Public_List",
                new { Query = query, PageNumber = pageNumber, PageSize = pageSize },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<PublicFunderRow>()).AsList();
            return new PublicFunderPage(
                rows.Select(MapPublicSummary).ToArray(), totalCount, pageNumber, pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("list published funders", exception);
        }
    }

    public async Task<PublicFunderDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Funder_Public_GetBySlug",
                new { Slug = slug },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<PublicFunderRow>();
            if (row is null)
            {
                return null;
            }

            var aliases = (await reader.ReadAsync<FunderAliasRow>())
                .Select(item => item.Alias)
                .ToArray();
            var opportunities = (await reader.ReadAsync<PublicFunderOpportunityRow>())
                .Select(item => new PublicFunderOpportunity(
                    item.FundingOpportunityPublicId,
                    item.Slug,
                    item.Title,
                    item.Summary,
                    item.SponsorName,
                    item.Currency?.Trim(),
                    item.MinAmount,
                    item.MaxAmount,
                    ToDateOnly(item.OpenDate),
                    ToDateOnly(item.CloseDate),
                    ToUtc(item.PublishedAtUtc)))
                .ToArray();
            return new PublicFunderDetails(
                row.FunderPublicId,
                row.Slug,
                row.Name,
                row.Description,
                row.WebsiteUrl,
                row.CountryCode?.Trim(),
                row.CountryName,
                aliases,
                ToUtc(row.PublishedAtUtc),
                opportunities);
        }
        catch (SqlException exception)
        {
            throw Wrap("read published funder", exception);
        }
    }

    private async Task<FundingEditorialMutation> ExecuteCommandAsync(
        string procedure,
        string operation,
        object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<FunderMutationRow>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return MapMutation(row, []);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private async Task<FundingEditorialMutation> ExecuteWorkflowAsync(
        string procedure,
        string operation,
        object parameters,
        bool readsIssues,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            FunderMutationRow row;
            IReadOnlyList<FundingReadinessIssue> issues;
            if (readsIssues)
            {
                using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                row = await reader.ReadSingleAsync<FunderMutationRow>();
                issues = (await reader.ReadAsync<FundingReadinessIssue>()).AsList();
            }
            else
            {
                row = await connection.QuerySingleAsync<FunderMutationRow>(new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                issues = [];
            }

            return MapMutation(row, issues);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static FundingEditorialMutation MapMutation(
        FunderMutationRow row,
        IReadOnlyList<FundingReadinessIssue> issues) => new(
        row.Succeeded,
        row.Code,
        row.FunderPublicId ?? Guid.Empty,
        (FundingPublicationStatus)(row.PublicationStatus ?? 0),
        row.ContentVersion ?? 0,
        row.RowVersion ?? [],
        row.WasReplay,
        issues,
        ToUtc(row.SubmittedAtUtc),
        ToUtc(row.ReviewedAtUtc),
        row.ReviewedByUserPublicId,
        ToUtc(row.PublishedAtUtc),
        row.RejectionReason);

    private static FunderSummary MapSummary(FunderRow row) => new(
        row.FunderPublicId,
        row.Slug,
        row.Name,
        row.Description,
        row.WebsiteUrl,
        row.CountryId,
        row.CountryCode?.Trim(),
        row.CountryName,
        (FundingPublicationStatus)row.PublicationStatus,
        row.IsActive,
        row.ContentVersion,
        ToUtc(row.UpdatedAtUtc),
        row.RowVersion);

    private static FunderDetails MapDetails(
        FunderRow row,
        IReadOnlyList<string> aliases,
        IReadOnlyList<FunderOpportunitySummary> opportunities) => new(
        row.FunderPublicId,
        row.Slug,
        row.Name,
        row.Description,
        row.WebsiteUrl,
        row.CountryId,
        row.CountryCode?.Trim(),
        row.CountryName,
        (FundingPublicationStatus)row.PublicationStatus,
        row.IsActive,
        row.ContentVersion,
        ToUtc(row.CreatedAtUtc),
        ToUtc(row.UpdatedAtUtc),
        row.RowVersion,
        aliases,
        ToUtc(row.SubmittedAtUtc),
        ToUtc(row.ReviewedAtUtc),
        row.ReviewedByUserPublicId,
        ToUtc(row.PublishedAtUtc),
        row.RejectionReason,
        opportunities);

    private static PublicFunderSummary MapPublicSummary(PublicFunderRow row) => new(
        row.FunderPublicId,
        row.Slug,
        row.Name,
        row.Description,
        row.WebsiteUrl,
        row.CountryCode?.Trim(),
        row.CountryName);

    private static string SerializeAliases(IReadOnlyList<string> aliases) =>
        JsonSerializer.Serialize(
            aliases.Select(alias => new { alias, isPrimary = false }),
            JsonOptions);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static FundingEditorialDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class FunderRow
    {
        public Guid FunderPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Name { get; init; } = string.Empty;
        public string? Description { get; init; }
        public string? WebsiteUrl { get; init; }
        public short? CountryId { get; init; }
        public string? CountryCode { get; init; }
        public string? CountryName { get; init; }
        public int ContentVersion { get; init; }
        public byte PublicationStatus { get; init; }
        public bool IsActive { get; init; }
        public DateTime? SubmittedAtUtc { get; init; }
        public DateTime? PublishedAtUtc { get; init; }
        public DateTime? ReviewedAtUtc { get; init; }
        public Guid? ReviewedByUserPublicId { get; init; }
        public string? RejectionReason { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class FunderAliasRow
    {
        public string Alias { get; init; } = string.Empty;
        public bool IsPrimary { get; init; }
        public bool IsActive { get; init; }
    }

    private sealed class FunderOpportunityRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Title { get; init; } = string.Empty;
        public byte Role { get; init; }
        public byte PublicationStatus { get; init; }
        public bool IsActive { get; init; }
    }

    private sealed class PublicFunderRow
    {
        public Guid FunderPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Name { get; init; } = string.Empty;
        public string? Description { get; init; }
        public string? WebsiteUrl { get; init; }
        public string? CountryCode { get; init; }
        public string? CountryName { get; init; }
        public DateTime PublishedAtUtc { get; init; }
    }

    private sealed class PublicFunderOpportunityRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Title { get; init; } = string.Empty;
        public string? Summary { get; init; }
        public string SponsorName { get; init; } = string.Empty;
        public string? Currency { get; init; }
        public decimal? MinAmount { get; init; }
        public decimal? MaxAmount { get; init; }
        public DateTime? OpenDate { get; init; }
        public DateTime? CloseDate { get; init; }
        public DateTime PublishedAtUtc { get; init; }
    }

    private sealed class FunderMutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? FunderPublicId { get; init; }
        public int? ContentVersion { get; init; }
        public byte? PublicationStatus { get; init; }
        public DateTime? SubmittedAtUtc { get; init; }
        public DateTime? PublishedAtUtc { get; init; }
        public DateTime? ReviewedAtUtc { get; init; }
        public Guid? ReviewedByUserPublicId { get; init; }
        public string? RejectionReason { get; init; }
        public byte[]? RowVersion { get; init; }
        public bool WasReplay { get; init; }
    }
}
