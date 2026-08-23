using System.Data;
using Dapper;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Organizations;

public sealed class SqlOrganizationRepository(
    ISqlConnectionFactory connectionFactory) : IOrganizationRepository
{
    public async Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            await connection.OpenAsync(cancellationToken);
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Catalogs_GetForOrganizationProfile",
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));

            var countries = (await reader.ReadAsync<ShortCatalogRow>()).Select(MapShort).ToArray();
            var regions = (await reader.ReadAsync<RegionRow>())
                .Select(row => new RegionOption(row.Id, row.CountryId, row.Code.Trim(), row.Name)).ToArray();
            var currencies = (await reader.ReadAsync<CurrencyRow>())
                .Select(row => new CurrencyOption(row.Code.Trim(), row.Name, row.MinorUnits)).ToArray();
            var categories = (await reader.ReadAsync<IntCatalogRow>()).Select(MapInt).ToArray();
            var fundingTypes = (await reader.ReadAsync<ShortCatalogRow>()).Select(MapShort).ToArray();
            var organizationTypes = (await reader.ReadAsync<ShortCatalogRow>()).Select(MapShort).ToArray();
            var legalEntityTypes = (await reader.ReadAsync<LegalEntityRow>())
                .Select(row => new LegalEntityTypeOption(row.Id, row.CountryId, row.Code, row.Name)).ToArray();
            var organizationSizes = (await reader.ReadAsync<ShortCatalogRow>()).Select(MapShort).ToArray();
            var beneficiaries = (await reader.ReadAsync<IntCatalogRow>()).Select(MapInt).ToArray();
            var projectTypes = (await reader.ReadAsync<IntCatalogRow>()).Select(MapInt).ToArray();
            var tags = (await reader.ReadAsync<LongCatalogRow>())
                .Select(row => new CatalogOption<long>(row.Id, row.Code, row.Name)).ToArray();
            var languages = (await reader.ReadAsync<ShortCatalogRow>()).Select(MapShort).ToArray();

            return new OrganizationCatalogs(
                countries, regions, currencies, categories, fundingTypes, organizationTypes,
                legalEntityTypes, organizationSizes, beneficiaries, projectTypes, tags, languages);
        }
        catch (SqlException exception)
        {
            throw Wrap("read organization catalogs", exception);
        }
    }

    public async Task<IReadOnlyList<OrganizationSummary>> ListForUserAsync(
        Guid userPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var rows = await connection.QueryAsync<OrganizationSummaryRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_Organization_ListForUser",
                new { UserPublicId = userPublicId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            return rows.Select(row => new OrganizationSummary(
                row.PublicId, row.Name, row.MembershipRole, row.ProfileStatus,
                row.ProfileCompleteness, row.ProfileVersion,
                new DateTimeOffset(DateTime.SpecifyKind(row.UpdatedAtUtc, DateTimeKind.Utc)))).ToArray();
        }
        catch (SqlException exception)
        {
            throw Wrap("list user organizations", exception);
        }
    }

    public async Task<PersistedOrganization> CreateAsync(
        Guid userPublicId,
        OrganizationProfileData profile,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<PersistedOrganizationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_Organization_CreateForUser",
                new
                {
                    UserPublicId = userPublicId,
                    profile.Name,
                    profile.HomeCountryId,
                    profile.OrganizationTypeId,
                    SnapshotJson = snapshotJson,
                    ContentHash = contentHash
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return MapPersisted(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("create organization", exception);
        }
    }

    public async Task<OrganizationProfile?> GetProfileAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_Organization_GetProfileByPublicId",
                new { OrganizationPublicId = organizationPublicId, UserPublicId = userPublicId },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 20,
                cancellationToken: cancellationToken));

            var role = await reader.ReadSingleAsync<byte>();
            var row = await reader.ReadSingleOrDefaultAsync<OrganizationProfileRow>();
            if (row is null) return null;
            var countries = (await reader.ReadAsync<ShortIdRow>()).Select(value => value.Id).ToArray();
            var regions = (await reader.ReadAsync<IntIdRow>()).Select(value => value.Id).ToArray();
            var categories = (await reader.ReadAsync<IntIdRow>()).Select(value => value.Id).ToArray();
            var beneficiaries = (await reader.ReadAsync<IntIdRow>()).Select(value => value.Id).ToArray();
            var projectTypes = (await reader.ReadAsync<IntIdRow>()).Select(value => value.Id).ToArray();
            var tags = (await reader.ReadAsync<LongIdRow>()).Select(value => value.Id).ToArray();
            var languages = (await reader.ReadAsync<LanguageRow>())
                .Select(value => new OrganizationLanguage(value.LanguageId, value.Proficiency)).ToArray();
            return MapProfile(row, role, countries, regions, categories, beneficiaries, projectTypes, tags, languages);
        }
        catch (SqlException exception) when (exception.Number is 51003 or 51203)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read organization profile", exception);
        }
    }

    public async Task<PersistedOrganization> UpdateProfileAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        byte[] expectedRowVersion,
        OrganizationProfileData profile,
        byte profileStatus,
        decimal profileCompleteness,
        string snapshotJson,
        byte[] contentHash,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId);
        parameters.Add("OrganizationPublicId", organizationPublicId);
        parameters.Add("ExpectedRowVersion", expectedRowVersion, DbType.Binary, size: 8);
        parameters.Add("Name", profile.Name);
        parameters.Add("LegalName", profile.LegalName);
        parameters.Add("TaxIdentifier", profile.TaxIdentifier);
        parameters.Add("HomeCountryId", profile.HomeCountryId);
        parameters.Add("OrganizationTypeId", profile.OrganizationTypeId);
        parameters.Add("LegalEntityTypeId", profile.LegalEntityTypeId);
        parameters.Add("OrganizationSizeId", profile.OrganizationSizeId);
        parameters.Add("EstablishedYear", profile.EstablishedYear);
        parameters.Add("WebsiteUrl", profile.WebsiteUrl);
        parameters.Add("Description", profile.Description);
        parameters.Add("PreviousFundingExperience", profile.PreviousFundingExperience);
        parameters.Add("ExperienceSummary", profile.ExperienceSummary);
        parameters.Add("AnnualBudgetMin", profile.AnnualBudgetMin);
        parameters.Add("AnnualBudgetMax", profile.AnnualBudgetMax);
        parameters.Add("AnnualBudgetCurrency", profile.AnnualBudgetCurrency);
        parameters.Add("DesiredFundingMin", profile.DesiredFundingMin);
        parameters.Add("DesiredFundingMax", profile.DesiredFundingMax);
        parameters.Add("DesiredFundingCurrency", profile.DesiredFundingCurrency);
        parameters.Add("ProfileStatus", profileStatus);
        parameters.Add("ProfileCompleteness", profileCompleteness);
        parameters.Add("SnapshotJson", snapshotJson);
        parameters.Add("ContentHash", contentHash, DbType.Binary, size: 32);
        parameters.Add("CountryIds", ToIdTable(profile.CountryIds).AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("RegionIds", ToIdTable(profile.RegionIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("CategoryIds", ToIdTable(profile.CategoryIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("BeneficiaryTypeIds", ToIdTable(profile.BeneficiaryTypeIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(profile.ProjectTypeIds).AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("TagIds", ToIdTable(profile.TagIds).AsTableValuedParameter("dbo.FundingPlatform_BigIntIdList"));
        parameters.Add("Languages", ToLanguageTable(profile.Languages).AsTableValuedParameter("dbo.FundingPlatform_OrganizationLanguageList"));

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<PersistedOrganizationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_Organization_UpdateProfileByPublicId",
                parameters,
                commandType: CommandType.StoredProcedure,
                commandTimeout: 30,
                cancellationToken: cancellationToken));
            return MapPersisted(row);
        }
        catch (SqlException exception)
        {
            throw Wrap("update organization profile", exception);
        }
    }

    private static DataTable ToIdTable<T>(IEnumerable<T> ids)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var id in ids) table.Rows.Add(id);
        return table;
    }

    private static DataTable ToLanguageTable(IEnumerable<OrganizationLanguage> languages)
    {
        var table = new DataTable();
        table.Columns.Add("LanguageId", typeof(short));
        table.Columns.Add("Proficiency", typeof(byte));
        foreach (var language in languages)
            table.Rows.Add(language.LanguageId, language.Proficiency.HasValue ? language.Proficiency.Value : DBNull.Value);
        return table;
    }

    private static CatalogOption<short> MapShort(ShortCatalogRow row) => new(row.Id, row.Code.Trim(), row.Name);
    private static CatalogOption<int> MapInt(IntCatalogRow row) => new(row.Id, row.Code, row.Name);
    private static PersistedOrganization MapPersisted(PersistedOrganizationRow row) =>
        new(row.PublicId, row.ProfileVersion, row.RowVersion);

    private static OrganizationProfile MapProfile(
        OrganizationProfileRow row, byte role, IReadOnlyList<short> countries,
        IReadOnlyList<int> regions, IReadOnlyList<int> categories,
        IReadOnlyList<int> beneficiaries, IReadOnlyList<int> projectTypes,
        IReadOnlyList<long> tags, IReadOnlyList<OrganizationLanguage> languages) =>
        new(row.PublicId, row.Name, row.LegalName, row.TaxIdentifier, row.HomeCountryId,
            row.OrganizationTypeId, row.LegalEntityTypeId, row.OrganizationSizeId,
            row.EstablishedYear, row.WebsiteUrl, row.Description, row.PreviousFundingExperience,
            row.ExperienceSummary, row.AnnualBudgetMin, row.AnnualBudgetMax,
            row.AnnualBudgetCurrency?.Trim(), row.DesiredFundingMin, row.DesiredFundingMax,
            row.DesiredFundingCurrency?.Trim(), row.ProfileStatus, row.ProfileCompleteness,
            row.ProfileVersion, role, row.RowVersion, countries, regions, categories,
            beneficiaries, projectTypes, tags, languages);

    private static OrganizationDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class ShortCatalogRow { public short Id { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; }
    private sealed class IntCatalogRow { public int Id { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; }
    private sealed class LongCatalogRow { public long Id { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; }
    private sealed class RegionRow { public int Id { get; set; } public short CountryId { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; }
    private sealed class CurrencyRow { public string Code { get; set; } = ""; public string Name { get; set; } = ""; public byte MinorUnits { get; set; } }
    private sealed class LegalEntityRow { public short Id { get; set; } public short? CountryId { get; set; } public string Code { get; set; } = ""; public string Name { get; set; } = ""; }
    private sealed class ShortIdRow { public short Id { get; set; } }
    private sealed class IntIdRow { public int Id { get; set; } }
    private sealed class LongIdRow { public long Id { get; set; } }
    private sealed class LanguageRow { public short LanguageId { get; set; } public byte? Proficiency { get; set; } }
    private sealed class PersistedOrganizationRow { public Guid PublicId { get; set; } public int ProfileVersion { get; set; } public byte[] RowVersion { get; set; } = []; }
    private sealed class OrganizationSummaryRow { public Guid PublicId { get; set; } public string Name { get; set; } = ""; public byte MembershipRole { get; set; } public byte ProfileStatus { get; set; } public decimal ProfileCompleteness { get; set; } public int ProfileVersion { get; set; } public DateTime UpdatedAtUtc { get; set; } }
    private sealed class OrganizationProfileRow
    {
        public Guid PublicId { get; set; }
        public string Name { get; set; } = "";
        public string? LegalName { get; set; }
        public string? TaxIdentifier { get; set; }
        public short HomeCountryId { get; set; }
        public short OrganizationTypeId { get; set; }
        public short? LegalEntityTypeId { get; set; }
        public short? OrganizationSizeId { get; set; }
        public short? EstablishedYear { get; set; }
        public string? WebsiteUrl { get; set; }
        public string? Description { get; set; }
        public byte PreviousFundingExperience { get; set; }
        public string? ExperienceSummary { get; set; }
        public decimal? AnnualBudgetMin { get; set; }
        public decimal? AnnualBudgetMax { get; set; }
        public string? AnnualBudgetCurrency { get; set; }
        public decimal? DesiredFundingMin { get; set; }
        public decimal? DesiredFundingMax { get; set; }
        public string? DesiredFundingCurrency { get; set; }
        public byte ProfileStatus { get; set; }
        public decimal ProfileCompleteness { get; set; }
        public int ProfileVersion { get; set; }
        public byte[] RowVersion { get; set; } = [];
    }
}
