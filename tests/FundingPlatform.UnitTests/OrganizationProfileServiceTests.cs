using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;

namespace FundingPlatform.UnitTests;

public sealed class OrganizationProfileServiceTests
{
    [Fact]
    public async Task Update_normalizes_lists_and_calculates_completeness_server_side()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);
        var profile = CompleteProfile() with
        {
            CountryIds = [152, 152],
            CategoryIds = [2, 1, 2]
        };

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], profile, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Success, result.Outcome);
        Assert.Equal(100m, repository.Completeness);
        Assert.Equal([152], repository.UpdatedProfile!.CountryIds);
        Assert.Equal([1, 2], repository.UpdatedProfile.CategoryIds);
        Assert.Equal<byte?>(2, repository.ProfileStatus);
        Assert.NotEmpty(repository.SnapshotJson!);
        Assert.Equal(32, repository.ContentHash!.Length);
    }

    [Fact]
    public async Task Update_rejects_invalid_money_range_before_repository()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with { DesiredFundingMin = 10_000, DesiredFundingMax = 5_000 },
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("desiredFundingMax", result.Errors!.Keys);
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_treats_null_collections_as_empty_for_put_replacement()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);
        var profile = CompleteProfile() with
        {
            CountryIds = null!,
            RegionIds = null!,
            CategoryIds = null!,
            BeneficiaryTypeIds = null!,
            ProjectTypeIds = null!,
            TagIds = null!,
            Languages = null!,
            FundingExperienceTypeIds = null
        };

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], profile, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Success, result.Outcome);
        Assert.Empty(repository.UpdatedProfile!.CountryIds);
        Assert.Empty(repository.UpdatedProfile.RegionIds);
        Assert.Empty(repository.UpdatedProfile.CategoryIds);
        Assert.Empty(repository.UpdatedProfile.BeneficiaryTypeIds);
        Assert.Empty(repository.UpdatedProfile.ProjectTypeIds);
        Assert.Empty(repository.UpdatedProfile.TagIds);
        Assert.Empty(repository.UpdatedProfile.Languages);
        Assert.Empty(repository.UpdatedProfile.FundingExperienceTypeIds!);
    }

    [Fact]
    public async Task Update_returns_all_required_field_errors_for_missing_required_values()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);
        var profile = CompleteProfile() with
        {
            Name = null!,
            HomeCountryId = 0,
            OrganizationTypeId = 0
        };

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], profile, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(
            ["homeCountryId", "name", "organizationTypeId"],
            result.Errors!.Keys.Order().ToArray());
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_returns_field_specific_errors_for_each_invalid_money_input()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);
        var profile = CompleteProfile() with
        {
            AnnualBudgetMin = -1,
            AnnualBudgetMax = -2,
            AnnualBudgetCurrency = "euro",
            DesiredFundingMin = 10_000,
            DesiredFundingMax = 5_000,
            DesiredFundingCurrency = null
        };

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], profile, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Equal(
            [
                "annualBudgetCurrency", "annualBudgetMax", "annualBudgetMin",
                "desiredFundingCurrency", "desiredFundingMax"
            ],
            result.Errors!.Keys.Order().ToArray());
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_accepts_a_bare_domain_and_persists_a_safe_https_url()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with { WebsiteUrl = "  onara.org  " },
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Success, result.Outcome);
        Assert.Equal("https://onara.org", repository.UpdatedProfile!.WebsiteUrl);
    }

    [Fact]
    public async Task Update_rejects_non_web_schemes()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with { WebsiteUrl = "javascript:alert(1)" },
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Equal("Ingresa un dominio válido, por ejemplo onara.org.", result.Errors!["websiteUrl"][0]);
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_normalizes_and_snapshots_optional_funding_experience_types()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with { FundingExperienceTypeIds = [4, 1, 4] },
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Success, result.Outcome);
        Assert.Equal([1, 4], repository.UpdatedProfile!.FundingExperienceTypeIds);
        Assert.Contains("\"fundingExperienceTypeIds\":[1,4]", repository.SnapshotJson,
            StringComparison.Ordinal);
        Assert.Equal(100m, repository.Completeness);
    }

    [Fact]
    public async Task Update_rejects_funder_types_without_prior_experience()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with
            {
                PreviousFundingExperience = 1,
                FundingExperienceTypeIds = [1]
            },
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("fundingExperienceTypeIds", result.Errors!.Keys);
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_normalizes_orders_and_snapshots_private_custom_taxonomy()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with
            {
                CustomTaxonomyValues =
                [
                    new(OrganizationCustomTaxonomyKind.Language, "  Mapudungun  ", "ignored"),
                    new(OrganizationCustomTaxonomyKind.ImpactArea, "Economía   circular", "ignored")
                ]
            }, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Success, result.Outcome);
        Assert.Collection(repository.UpdatedProfile!.CustomTaxonomyValues!,
            value =>
            {
                Assert.Equal(OrganizationCustomTaxonomyKind.ImpactArea, value.Kind);
                Assert.Equal("Economía circular", value.Name);
                Assert.Equal("ECONOMIA CIRCULAR", value.NormalizedName);
            },
            value => Assert.Equal(OrganizationCustomTaxonomyKind.Language, value.Kind));
        using var snapshot = System.Text.Json.JsonDocument.Parse(repository.SnapshotJson!);
        var firstCustom = snapshot.RootElement.GetProperty("customTaxonomyValues")[0];
        Assert.Equal(1, firstCustom.GetProperty("kind").GetByte());
        Assert.Equal("Economía circular", firstCustom.GetProperty("name").GetString());
        Assert.DoesNotContain("normalizedName", repository.SnapshotJson, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Update_rejects_accent_insensitive_equivalent_of_official_option()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with
            {
                CustomTaxonomyValues =
                [new(OrganizationCustomTaxonomyKind.ImpactArea, " educacion ", "ignored")]
            }, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("customImpactAreas", result.Errors!.Keys);
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public async Task Update_rejects_more_than_five_custom_values_in_one_dimension()
    {
        var repository = new StubRepository();
        var service = new OrganizationProfileService(repository);
        var custom = Enumerable.Range(1, 6)
            .Select(index => new OrganizationCustomTaxonomyValue(
                OrganizationCustomTaxonomyKind.Language, $"Idioma {index}", "ignored"))
            .ToArray();

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8],
            CompleteProfile() with { CustomTaxonomyValues = custom }, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("customLanguages", result.Errors!.Keys);
        Assert.Null(repository.UpdatedProfile);
    }

    [Fact]
    public void Completeness_accepts_custom_values_in_the_four_taxonomy_dimensions()
    {
        var profile = CompleteProfile() with
        {
            CategoryIds = [], BeneficiaryTypeIds = [], ProjectTypeIds = [], Languages = [],
            CustomTaxonomyValues =
            [
                new(OrganizationCustomTaxonomyKind.ImpactArea, "Área propia", "AREA PROPIA"),
                new(OrganizationCustomTaxonomyKind.BeneficiaryType, "Población propia", "POBLACION PROPIA"),
                new(OrganizationCustomTaxonomyKind.ProjectType, "Proyecto propio", "PROYECTO PROPIO"),
                new(OrganizationCustomTaxonomyKind.Language, "Idioma propio", "IDIOMA PROPIO")
            ]
        };

        Assert.Equal(100m, OrganizationProfileService.CalculateCompleteness(profile));
    }

    [Fact]
    public async Task Create_maps_owned_limit_without_leaking_database_detail()
    {
        var repository = new StubRepository { CreateErrorNumber = 51202 };
        var service = new OrganizationProfileService(repository);

        var result = await service.CreateAsync(
            Guid.NewGuid(), "Fundación Demo", 152, 2, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.OwnedLimitReached, result.Outcome);
    }

    [Fact]
    public async Task Update_maps_legacy_snapshot_guard_to_a_sanitized_conflict()
    {
        var repository = new StubRepository { UpdateErrorNumber = 51011 };
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], CompleteProfile(),
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.Conflict, result.Outcome);
        Assert.Null(result.Errors);
    }

    [Fact]
    public async Task Update_maps_database_catalog_rejection_to_the_funding_experience_field()
    {
        var repository = new StubRepository { UpdateErrorNumber = 51012 };
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], CompleteProfile(),
            CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.ValidationFailed, result.Outcome);
        Assert.Contains("fundingExperienceTypeIds", result.Errors!.Keys);
    }

    [Theory]
    [InlineData(51013, OrganizationWriteOutcome.Conflict)]
    [InlineData(51014, OrganizationWriteOutcome.ValidationFailed)]
    public async Task Update_maps_custom_taxonomy_database_errors_without_leaking_details(
        int errorNumber, OrganizationWriteOutcome expected)
    {
        var repository = new StubRepository { UpdateErrorNumber = errorNumber };
        var service = new OrganizationProfileService(repository);

        var result = await service.UpdateAsync(
            Guid.NewGuid(), Guid.NewGuid(), new byte[8], CompleteProfile(), CancellationToken.None);

        Assert.Equal(expected, result.Outcome);
    }

    private static OrganizationProfileData CompleteProfile() => new(
        "Fundación Demo", "Fundación Demo", "TEST-1", 152, 2, 1, 1, 2020,
        "https://example.org", "Descripción de impacto", 2, "Experiencia previa",
        1_000, 2_000, "CLP", 3_000, 4_000, "USD",
        [152], [7], [1], [1], [1], [], [new OrganizationLanguage(1, 5)], [1, 4]);

    private sealed class StubRepository : IOrganizationRepository
    {
        public int? CreateErrorNumber { get; set; }
        public int? UpdateErrorNumber { get; set; }
        public OrganizationProfileData? UpdatedProfile { get; private set; }
        public decimal? Completeness { get; private set; }
        public byte? ProfileStatus { get; private set; }
        public string? SnapshotJson { get; private set; }
        public byte[]? ContentHash { get; private set; }

        public Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken) =>
            Task.FromResult(new OrganizationCatalogs(
                [], [], [], [new CatalogOption<int>(1, "EDUCATION", "Educación")], [], [], [],
                [], [], [], [], [new CatalogOption<short>(1, "es", "Español")], [], []));

        public Task<IReadOnlyList<OrganizationSummary>> ListForUserAsync(Guid userPublicId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PersistedOrganization> CreateAsync(Guid userPublicId, OrganizationProfileData profile,
            string snapshotJson, byte[] contentHash, CancellationToken cancellationToken)
        {
            if (CreateErrorNumber.HasValue)
                throw new OrganizationDataException("create", CreateErrorNumber.Value, new Exception());
            return Task.FromResult(new PersistedOrganization(Guid.NewGuid(), 1, new byte[8]));
        }

        public Task<OrganizationProfile?> GetProfileAsync(Guid userPublicId, Guid organizationPublicId,
            CancellationToken cancellationToken) => throw new NotSupportedException();

        public Task<PersistedOrganization> UpdateProfileAsync(Guid userPublicId, Guid organizationPublicId,
            byte[] expectedRowVersion, OrganizationProfileData profile, byte profileStatus,
            decimal profileCompleteness, string snapshotJson, byte[] contentHash,
            CancellationToken cancellationToken)
        {
            if (UpdateErrorNumber.HasValue)
                throw new OrganizationDataException(
                    "update", UpdateErrorNumber.Value, new Exception());
            UpdatedProfile = profile;
            ProfileStatus = profileStatus;
            Completeness = profileCompleteness;
            SnapshotJson = snapshotJson;
            ContentHash = contentHash;
            return Task.FromResult(new PersistedOrganization(organizationPublicId, 2, new byte[8]));
        }
    }
}
