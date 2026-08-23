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
        Assert.Contains("desiredFunding", result.Errors!.Keys);
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
    public async Task Create_maps_owned_limit_without_leaking_database_detail()
    {
        var repository = new StubRepository { CreateErrorNumber = 51202 };
        var service = new OrganizationProfileService(repository);

        var result = await service.CreateAsync(
            Guid.NewGuid(), "Fundación Demo", 152, 2, CancellationToken.None);

        Assert.Equal(OrganizationWriteOutcome.OwnedLimitReached, result.Outcome);
    }

    private static OrganizationProfileData CompleteProfile() => new(
        "Fundación Demo", "Fundación Demo", "TEST-1", 152, 2, 1, 1, 2020,
        "https://example.org", "Descripción de impacto", 2, "Experiencia previa",
        1_000, 2_000, "CLP", 3_000, 4_000, "USD",
        [152], [7], [1], [1], [1], [], [new OrganizationLanguage(1, 5)]);

    private sealed class StubRepository : IOrganizationRepository
    {
        public int? CreateErrorNumber { get; set; }
        public OrganizationProfileData? UpdatedProfile { get; private set; }
        public decimal? Completeness { get; private set; }
        public byte? ProfileStatus { get; private set; }
        public string? SnapshotJson { get; private set; }
        public byte[]? ContentHash { get; private set; }

        public Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();

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
            UpdatedProfile = profile;
            ProfileStatus = profileStatus;
            Completeness = profileCompleteness;
            SnapshotJson = snapshotJson;
            ContentHash = contentHash;
            return Task.FromResult(new PersistedOrganization(organizationPublicId, 2, new byte[8]));
        }
    }
}
