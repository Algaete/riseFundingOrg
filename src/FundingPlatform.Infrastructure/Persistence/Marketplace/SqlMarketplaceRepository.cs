using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Core.Projects;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Marketplace;

public sealed class SqlMarketplaceRepository(
    ISqlConnectionFactory connectionFactory) : IMarketplaceRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<MarketplaceProjectPage> SearchProjectsAsync(
        MarketplaceProjectFilters filters,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("Query", filters.Query);
        parameters.Add("Currency", filters.Currency, DbType.AnsiStringFixedLength, size: 3);
        parameters.Add("ProjectStatus", filters.ProjectStatus.HasValue
            ? (byte?)filters.ProjectStatus.Value
            : null);
        parameters.Add("Sort", SortCode(filters.Sort));
        parameters.Add("PageNumber", filters.PageNumber);
        parameters.Add("PageSize", filters.PageSize);
        parameters.Add("CountryIds", ToIdTable(filters.CountryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("CategoryIds", ToIdTable(filters.CategoryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(filters.ProjectTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("MatchedCount", dbType: DbType.Int64, direction: ParameterDirection.Output);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectMarketplace_Search",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<TotalCountRow>();
            var rows = await reader.ReadAsync<MarketplaceProjectRow>();
            return new MarketplaceProjectPage(
                rows.Select(MapSummary).ToArray(),
                metadata.TotalCount,
                filters.PageNumber,
                filters.PageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("search projects", exception);
        }
    }

    public async Task<PublicProjectDetails?> GetProjectBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<MarketplaceProjectDetailsRow>(
                new CommandDefinition(
                    "dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug",
                    new { Slug = slug },
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 15,
                    cancellationToken: cancellationToken));
            return row is null ? null : MapDetails(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("read project", exception);
        }
        catch (JsonException exception)
        {
            throw new MarketplaceDataException("read project contract", -1, exception);
        }
    }

    public async Task<MarketplaceOrganizationProfile?> GetOrganizationAsync(
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationMarketplace_Get",
                new { OrganizationPublicId = organizationPublicId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));
            var organization = await reader.ReadSingleOrDefaultAsync<MarketplaceOrganizationRow>();
            if (organization is null)
            {
                return null;
            }

            var countries = (await reader.ReadAsync<ShortCatalogRow>())
                .Select(MapShortCatalog).ToArray();
            var regions = (await reader.ReadAsync<RegionRow>())
                .Select(row => new PublicOrganizationRegion(
                    row.Id, row.CountryId, row.Code, row.Name)).ToArray();
            var categories = (await reader.ReadAsync<IntCatalogRow>())
                .Select(MapIntCatalog).ToArray();
            var beneficiaryTypes = (await reader.ReadAsync<IntCatalogRow>())
                .Select(MapIntCatalog).ToArray();
            var projectTypes = (await reader.ReadAsync<IntCatalogRow>())
                .Select(MapIntCatalog).ToArray();
            var projectRows = await reader.ReadAsync<OrganizationProjectRow>();
            var publicOrganization = new PublicProjectOrganization(
                organization.OrganizationPublicId,
                organization.Name,
                organization.WebsiteUrl);

            return new MarketplaceOrganizationProfile(
                organization.OrganizationPublicId,
                organization.Name,
                organization.Description,
                organization.WebsiteUrl,
                organization.EstablishedYear,
                new PublicOrganizationCatalogItem<short>(
                    organization.HomeCountryId,
                    organization.HomeCountryCode,
                    organization.HomeCountryName),
                new PublicOrganizationCatalogItem<short>(
                    organization.OrganizationTypeId,
                    organization.OrganizationTypeCode,
                    organization.OrganizationTypeName),
                organization.OrganizationSizeId.HasValue
                    ? new PublicOrganizationCatalogItem<short>(
                        organization.OrganizationSizeId.Value,
                        organization.OrganizationSizeCode!,
                        organization.OrganizationSizeName!)
                    : null,
                countries,
                regions,
                categories,
                beneficiaryTypes,
                projectTypes,
                projectRows.Select(row => MapSummary(row, publicOrganization)).ToArray());
        }
        catch (SqlException exception)
        {
            throw Wrap("read organization", exception);
        }
    }

    private static MarketplaceProjectSummary MapSummary(MarketplaceProjectRow row) =>
        new(
            row.ProjectPublicId,
            row.Slug,
            row.Title,
            row.Summary,
            (ProjectStatus)row.ProjectStatus,
            ToDateOnly(row.StartDate),
            ToDateOnly(row.EndDate),
            row.BudgetTotal,
            row.ConfirmedFunding,
            row.Currency?.Trim(),
            row.FundingGap,
            ToUtc(row.PublishedAtUtc),
            new PublicProjectOrganization(
                row.OrganizationPublicId,
                row.OrganizationName,
                row.OrganizationWebsiteUrl));

    private static MarketplaceProjectSummary MapSummary(
        OrganizationProjectRow row,
        PublicProjectOrganization organization) =>
        new(
            row.ProjectPublicId,
            row.Slug,
            row.Title,
            row.Summary,
            (ProjectStatus)row.ProjectStatus,
            ToDateOnly(row.StartDate),
            ToDateOnly(row.EndDate),
            row.BudgetTotal,
            row.ConfirmedFunding,
            row.Currency?.Trim(),
            row.FundingGap,
            ToUtc(row.PublishedAtUtc),
            organization);

    private static PublicProjectDetails MapDetails(MarketplaceProjectDetailsRow row) =>
        new(
            row.ProjectPublicId,
            row.Slug,
            row.Title,
            row.Summary,
            row.Description,
            (ProjectStatus)row.ProjectStatus,
            ToDateOnly(row.StartDate),
            ToDateOnly(row.EndDate),
            row.BudgetTotal,
            row.ConfirmedFunding,
            row.Currency?.Trim(),
            row.FundingGap,
            ToUtc(row.PublishedAtUtc),
            new PublicProjectOrganization(
                row.OrganizationPublicId,
                row.OrganizationName,
                row.OrganizationWebsiteUrl),
            Deserialize<PublicProjectTaxonomyItem>(row.CountriesJson),
            Deserialize<PublicProjectRegion>(row.RegionsJson),
            Deserialize<PublicProjectTaxonomyItem>(row.CategoriesJson),
            Deserialize<PublicProjectTaxonomyItem>(row.BeneficiaryTypesJson),
            Deserialize<PublicProjectTaxonomyItem>(row.ProjectTypesJson));

    private static IReadOnlyList<T> Deserialize<T>(string? json) =>
        string.IsNullOrWhiteSpace(json)
            ? []
            : JsonSerializer.Deserialize<T[]>(json, JsonOptions) ?? [];

    private static DataTable ToIdTable<T>(IEnumerable<T> ids)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var id in ids)
        {
            table.Rows.Add(id);
        }

        return table;
    }

    private static string SortCode(MarketplaceProjectSort sort) => sort switch
    {
        MarketplaceProjectSort.Newest => "newest",
        MarketplaceProjectSort.Title => "title",
        MarketplaceProjectSort.FundingGapDescending => "funding-gap-desc",
        _ => throw new ArgumentOutOfRangeException(nameof(sort))
    };

    private static PublicOrganizationCatalogItem<short> MapShortCatalog(ShortCatalogRow row) =>
        new(row.Id, row.Code.Trim(), row.Name);

    private static PublicOrganizationCatalogItem<int> MapIntCatalog(IntCatalogRow row) =>
        new(row.Id, row.Code, row.Name);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static MarketplaceDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class TotalCountRow
    {
        public long TotalCount { get; init; }
    }

    private class OrganizationProjectRow
    {
        public Guid ProjectPublicId { get; init; }
        public string Slug { get; init; } = "";
        public string Title { get; init; } = "";
        public string? Summary { get; init; }
        public byte ProjectStatus { get; init; }
        public DateTime? StartDate { get; init; }
        public DateTime? EndDate { get; init; }
        public decimal? BudgetTotal { get; init; }
        public decimal? ConfirmedFunding { get; init; }
        public string? Currency { get; init; }
        public decimal? FundingGap { get; init; }
        public DateTime PublishedAtUtc { get; init; }
    }

    private class MarketplaceProjectRow : OrganizationProjectRow
    {
        public Guid OrganizationPublicId { get; init; }
        public string OrganizationName { get; init; } = "";
        public string? OrganizationWebsiteUrl { get; init; }
    }

    private sealed class MarketplaceProjectDetailsRow : MarketplaceProjectRow
    {
        public string? Description { get; init; }
        public string CountriesJson { get; init; } = "[]";
        public string RegionsJson { get; init; } = "[]";
        public string CategoriesJson { get; init; } = "[]";
        public string BeneficiaryTypesJson { get; init; } = "[]";
        public string ProjectTypesJson { get; init; } = "[]";
    }

    private sealed class MarketplaceOrganizationRow
    {
        public Guid OrganizationPublicId { get; init; }
        public string Name { get; init; } = "";
        public string? Description { get; init; }
        public string? WebsiteUrl { get; init; }
        public short? EstablishedYear { get; init; }
        public short HomeCountryId { get; init; }
        public string HomeCountryCode { get; init; } = "";
        public string HomeCountryName { get; init; } = "";
        public short OrganizationTypeId { get; init; }
        public string OrganizationTypeCode { get; init; } = "";
        public string OrganizationTypeName { get; init; } = "";
        public short? OrganizationSizeId { get; init; }
        public string? OrganizationSizeCode { get; init; }
        public string? OrganizationSizeName { get; init; }
    }

    private sealed class ShortCatalogRow
    {
        public short Id { get; init; }
        public string Code { get; init; } = "";
        public string Name { get; init; } = "";
    }

    private sealed class IntCatalogRow
    {
        public int Id { get; init; }
        public string Code { get; init; } = "";
        public string Name { get; init; } = "";
    }

    private sealed class RegionRow
    {
        public int Id { get; init; }
        public short CountryId { get; init; }
        public string Code { get; init; } = "";
        public string Name { get; init; } = "";
    }
}
