using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingOpportunityWorkspaceRepository(
    ISqlConnectionFactory connectionFactory) : IFundingOpportunityWorkspaceRepository
{
    private const int NotFoundErrorNumber = 52001;

    public async Task<WorkspaceFundingOpportunityPage?> SearchAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingOpportunitySearchFilters filters,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var parameters = new DynamicParameters();
            parameters.Add("UserPublicId", userPublicId);
            parameters.Add("OrganizationPublicId", organizationPublicId);
            parameters.Add("Query", filters.Query);
            parameters.Add("Sponsor", filters.Sponsor);
            parameters.Add("MinAmount", filters.MinimumAmount);
            parameters.Add("MaxAmount", filters.MaximumAmount);
            parameters.Add("Currency", filters.Currency);
            parameters.Add("ClosingFrom", ToDateTime(filters.ClosingFrom));
            parameters.Add("ClosingTo", ToDateTime(filters.ClosingTo));
            parameters.Add("OnlyOpen", filters.OnlyOpen);
            parameters.Add("Sort", ToSortCode(filters.Sort));
            parameters.Add("PageNumber", filters.PageNumber);
            parameters.Add("PageSize", filters.PageSize);
            AddFilterTables(parameters, filters);

            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var header = await reader.ReadSingleAsync<SearchHeaderRow>();
            var rows = (await reader.ReadAsync<SummaryRow>()).AsList();
            return new WorkspaceFundingOpportunityPage(
                rows.Select(MapSummary).ToArray(),
                header.TotalCount,
                filters.PageNumber,
                filters.PageSize,
                NormalizeSearchMode(header.SearchMode, filters.Query));
        }
        catch (SqlException exception) when (exception.Number == NotFoundErrorNumber)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("search organization funding opportunities", exception);
        }
    }

    public async Task<WorkspaceFundingOpportunityDetails?> GetPublishedAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid? fundingOpportunityPublicId,
        string? slug,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_OrganizationGet",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    FundingOpportunityPublicId = fundingOpportunityPublicId,
                    Slug = slug
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<DetailsRow>();
            if (row is null)
            {
                return null;
            }

            var countries = (await reader.ReadAsync<ShortIdRow>())
                .Select(item => item.Id).ToArray();
            var regions = (await reader.ReadAsync<IntIdRow>())
                .Select(item => item.Id).ToArray();
            var categories = (await reader.ReadAsync<IntIdRow>())
                .Select(item => item.Id).ToArray();
            var beneficiaries = (await reader.ReadAsync<IntIdRow>())
                .Select(item => item.Id).ToArray();
            var projectTypes = (await reader.ReadAsync<IntIdRow>())
                .Select(item => item.Id).ToArray();
            var tags = (await reader.ReadAsync<LongIdRow>())
                .Select(item => item.Id).ToArray();
            var organizationTypes = (await reader.ReadAsync<EligibilityTypeRow>())
                .Select(item => new FundingOpportunityEligibilityType(
                    item.Id, item.EligibilityMode)).ToArray();
            var legalEntityTypes = (await reader.ReadAsync<EligibilityTypeRow>())
                .Select(item => new FundingOpportunityEligibilityType(
                    item.Id, item.EligibilityMode)).ToArray();
            var languages = (await reader.ReadAsync<LanguageRow>())
                .Select(item => new FundingOpportunityLanguage(
                    item.Id, item.LanguagePurpose)).ToArray();
            var funders = (await reader.ReadAsync<FunderRow>())
                .Select(item => new FundingOpportunityFunder(
                    item.FunderPublicId,
                    item.Slug,
                    item.Name,
                    (FunderOpportunityRole)item.Role)).ToArray();
            var sources = (await reader.ReadAsync<SourceRow>())
                .Select(item => new WorkspaceFundingOpportunitySource(
                    item.FundingSourceId,
                    item.SourceName,
                    item.ExternalId,
                    item.SourceUrl,
                    ToUtc(item.FirstSeenAtUtc),
                    ToUtc(item.LastSeenAtUtc),
                    item.IsPrimary,
                    item.IsActive)).ToArray();

            return new WorkspaceFundingOpportunityDetails(
                row.FundingOpportunityPublicId,
                row.Slug,
                row.Title,
                row.Description,
                row.Summary,
                row.SponsorName,
                row.SponsorUrl,
                row.ApplicationUrl,
                row.IssuerCountryId,
                row.FundingTypeId,
                row.Currency?.Trim(),
                row.MinAmount,
                row.MaxAmount,
                (FundingAmountStatus)row.AmountStatus,
                ToDateOnly(row.OpenDate),
                ToDateOnly(row.CloseDate),
                ToUtc(row.CloseAtUtc),
                row.DeadlineTimeZoneId,
                (FundingDeadlineType)row.DeadlineType,
                (FundingDeadlinePrecision)row.DeadlinePrecision,
                row.EligibilityDescription,
                row.Requirements,
                row.Objectives,
                row.AllowedActivities,
                row.ExcludedActivities,
                row.Restrictions,
                row.TargetOrganizationsDescription,
                row.TargetPopulationsDescription,
                row.MinimumOperatingYears,
                row.RequiresLegalEntity,
                row.RequiresPriorExperience,
                row.RequiresCofunding,
                row.CofundingPercentage,
                (FundingGeographicScope)row.GeographicScope,
                (FundingRemoteApplication)row.RemoteApplication,
                ToUtc(row.LastVerifiedAtUtc ?? row.PublishedAtUtc),
                row.DataQualityScore,
                row.ContentVersion,
                ToUtc(row.PublishedAtUtc),
                row.PrimaryFunderPublicId,
                row.PrimaryFunderSlug,
                row.PrimaryFunderName,
                row.SourceName,
                row.SourceUrl,
                row.ExternalId,
                row.IsFavorite,
                countries,
                regions,
                categories,
                beneficiaries,
                projectTypes,
                tags,
                organizationTypes,
                legalEntityTypes,
                languages,
                funders,
                sources);
        }
        catch (SqlException exception) when (exception.Number == NotFoundErrorNumber)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read organization funding opportunity", exception);
        }
    }

    public async Task<WorkspaceFundingOpportunityPage?> ListFavoritesAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Favorite_List",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    PageNumber = pageNumber,
                    PageSize = pageSize
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<SummaryRow>()).AsList();
            return new WorkspaceFundingOpportunityPage(
                rows.Select(MapSummary).ToArray(),
                totalCount,
                pageNumber,
                pageSize);
        }
        catch (SqlException exception) when (exception.Number == NotFoundErrorNumber)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("list organization funding favorites", exception);
        }
    }

    public Task<FundingFavoriteMutation> PutFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken) =>
        MutateFavoriteAsync(
            "dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Put",
            "save organization funding favorite",
            userPublicId,
            organizationPublicId,
            fundingOpportunityPublicId,
            cancellationToken);

    public Task<FundingFavoriteMutation> DeleteFavoriteAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken) =>
        MutateFavoriteAsync(
            "dbo.FundingPlatform_usp_FundingOpportunity_Favorite_Delete",
            "delete organization funding favorite",
            userPublicId,
            organizationPublicId,
            fundingOpportunityPublicId,
            cancellationToken);

    private async Task<FundingFavoriteMutation> MutateFavoriteAsync(
        string procedure,
        string operation,
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingOpportunityPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var parameters = new DynamicParameters();
            parameters.Add("UserPublicId", userPublicId);
            parameters.Add("OrganizationPublicId", organizationPublicId);
            parameters.Add("FundingOpportunityPublicId", fundingOpportunityPublicId);

            var row = await connection.QuerySingleAsync<FavoriteMutationRow>(
                new CommandDefinition(
                    procedure,
                    parameters,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 15,
                    cancellationToken: cancellationToken));
            var outcome = row.Code switch
            {
                "created" => FundingFavoriteMutationOutcome.Created,
                "deleted" => FundingFavoriteMutationOutcome.Deleted,
                "unchanged" => FundingFavoriteMutationOutcome.Unchanged,
                _ => throw new InvalidOperationException(
                    "SQL returned an unknown favorite mutation outcome.")
            };
            return new FundingFavoriteMutation(
                outcome,
                row.FundingOpportunityPublicId,
                ToUtc(row.CreatedAtUtc));
        }
        catch (SqlException exception) when (exception.Number == NotFoundErrorNumber)
        {
            return new FundingFavoriteMutation(
                FundingFavoriteMutationOutcome.NotFound,
                fundingOpportunityPublicId,
                null);
        }
        catch (SqlException exception)
        {
            throw Wrap(operation, exception);
        }
    }

    private static void AddFilterTables(
        DynamicParameters parameters,
        FundingOpportunitySearchFilters filters)
    {
        parameters.Add("CountryIds", ToIdTable(filters.CountryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("RegionIds", ToIdTable(filters.RegionIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("CategoryIds", ToIdTable(filters.CategoryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("TagIds", ToIdTable(filters.TagIds)
            .AsTableValuedParameter("dbo.FundingPlatform_BigIntIdList"));
        parameters.Add("BeneficiaryTypeIds", ToIdTable(filters.BeneficiaryTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(filters.ProjectTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("FundingTypeIds", ToIdTable(filters.FundingTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("OrganizationTypeIds", ToIdTable(filters.OrganizationTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("FunderPublicIds", ToIdTable(filters.FunderPublicIds)
            .AsTableValuedParameter("dbo.FundingPlatform_GuidIdList"));
    }

    private static DataTable ToIdTable<T>(IEnumerable<T> values)
    {
        var table = new DataTable();
        table.Columns.Add("Id", Nullable.GetUnderlyingType(typeof(T)) ?? typeof(T));
        foreach (var value in values)
        {
            table.Rows.Add(value);
        }

        return table;
    }

    private static WorkspaceFundingOpportunitySummary MapSummary(SummaryRow row) => new(
        row.FundingOpportunityPublicId,
        row.Slug,
        row.Title,
        row.Summary,
        row.SponsorName,
        row.Currency?.Trim(),
        row.MinAmount,
        row.MaxAmount,
        ToDateOnly(row.OpenDate),
        ToDateOnly(row.CloseDate),
        ToUtc(row.CloseAtUtc),
        (FundingDeadlineType)row.DeadlineType,
        (FundingDeadlinePrecision)row.DeadlinePrecision,
        ToUtc(row.PublishedAtUtc),
        row.DataQualityScore,
        row.PrimaryFunderPublicId,
        row.PrimaryFunderName,
        row.SourceName,
        row.SourceUrl,
        row.IsFavorite);

    private static string ToSortCode(FundingOpportunitySearchSort sort) => sort switch
    {
        FundingOpportunitySearchSort.Relevance => "relevance",
        FundingOpportunitySearchSort.ClosingSoon => "closing-soon",
        FundingOpportunitySearchSort.Newest => "newest",
        FundingOpportunitySearchSort.AmountAscending => "amount-asc",
        FundingOpportunitySearchSort.AmountDescending => "amount-desc",
        _ => throw new ArgumentOutOfRangeException(nameof(sort))
    };

    private static string NormalizeSearchMode(string? value, string? query) => value switch
    {
        "full-text" => "full-text",
        "literal-fallback" => "literal-fallback",
        "filtered" => "filtered",
        "none" => "none",
        null when string.IsNullOrWhiteSpace(query) => "none",
        _ => "literal-fallback"
    };

    private static DateTime? ToDateTime(DateOnly? value) =>
        value?.ToDateTime(TimeOnly.MinValue);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;

    private static FundingOpportunityWorkspaceDataException Wrap(
        string operation,
        SqlException exception) => new(operation, exception.Number, exception);

    private sealed class SearchHeaderRow
    {
        public long TotalCount { get; init; }
        public string? SearchMode { get; init; }
    }

    private class SummaryRow
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
        public DateTime? CloseAtUtc { get; init; }
        public byte DeadlineType { get; init; }
        public byte DeadlinePrecision { get; init; }
        public DateTime PublishedAtUtc { get; init; }
        public decimal DataQualityScore { get; init; }
        public Guid PrimaryFunderPublicId { get; init; }
        public string PrimaryFunderName { get; init; } = string.Empty;
        public string SourceName { get; init; } = string.Empty;
        public string SourceUrl { get; init; } = string.Empty;
        public bool IsFavorite { get; init; }
    }

    private sealed class DetailsRow : SummaryRow
    {
        public string? Description { get; init; }
        public string? SponsorUrl { get; init; }
        public string? ApplicationUrl { get; init; }
        public short? IssuerCountryId { get; init; }
        public short? FundingTypeId { get; init; }
        public byte AmountStatus { get; init; }
        public string? DeadlineTimeZoneId { get; init; }
        public string? EligibilityDescription { get; init; }
        public string? Requirements { get; init; }
        public string? Objectives { get; init; }
        public string? AllowedActivities { get; init; }
        public string? ExcludedActivities { get; init; }
        public string? Restrictions { get; init; }
        public string? TargetOrganizationsDescription { get; init; }
        public string? TargetPopulationsDescription { get; init; }
        public short? MinimumOperatingYears { get; init; }
        public bool? RequiresLegalEntity { get; init; }
        public bool? RequiresPriorExperience { get; init; }
        public bool? RequiresCofunding { get; init; }
        public decimal? CofundingPercentage { get; init; }
        public byte GeographicScope { get; init; }
        public byte RemoteApplication { get; init; }
        public DateTime? LastVerifiedAtUtc { get; init; }
        public int ContentVersion { get; init; }
        public string PrimaryFunderSlug { get; init; } = string.Empty;
        public string? ExternalId { get; init; }
    }

    private sealed class ShortIdRow
    {
        public short Id { get; init; }
    }

    private sealed class IntIdRow
    {
        public int Id { get; init; }
    }

    private sealed class LongIdRow
    {
        public long Id { get; init; }
    }

    private sealed class EligibilityTypeRow
    {
        public short Id { get; init; }
        public byte EligibilityMode { get; init; }
    }

    private sealed class LanguageRow
    {
        public short Id { get; init; }
        public byte LanguagePurpose { get; init; }
    }

    private sealed class FunderRow
    {
        public Guid FunderPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Name { get; init; } = string.Empty;
        public byte Role { get; init; }
    }

    private sealed class SourceRow
    {
        public int FundingSourceId { get; init; }
        public string SourceName { get; init; } = string.Empty;
        public string? ExternalId { get; init; }
        public string SourceUrl { get; init; } = string.Empty;
        public DateTime FirstSeenAtUtc { get; init; }
        public DateTime LastSeenAtUtc { get; init; }
        public bool IsPrimary { get; init; }
        public bool IsActive { get; init; }
    }

    private sealed class FavoriteMutationRow
    {
        public string Code { get; init; } = string.Empty;
        public Guid FundingOpportunityPublicId { get; init; }
        public DateTime? CreatedAtUtc { get; init; }
    }
}
