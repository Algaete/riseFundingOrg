using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;

namespace FundingPlatform.IntegrationTests;

public sealed class OrganizationEndpointTests : IClassFixture<ApiFactory>, IDisposable
{
    private const string JwtIssuer = "https://testing.fundingplatform.local";
    private const string JwtAudience = "FundingPlatform.Tests";
    private const string ProfilePath =
        "/api/v1/organizations/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/profile";
    private static readonly byte[] SigningKey = new byte[64];
    private static readonly Guid UserId =
        Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid OrganizationId =
        Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    private readonly StubRepository repository = new();
    private readonly WebApplicationFactory<Program> application;
    private readonly HttpClient client;

    public OrganizationEndpointTests(ApiFactory factory)
    {
        application = factory.WithWebHostBuilder(builder =>
            builder.ConfigureTestServices(services =>
            {
                services.RemoveAll<IOrganizationRepository>();
                services.AddSingleton<IOrganizationRepository>(repository);
            }));
        client = application.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false
        });
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Put_profile_treats_omitted_or_null_collections_as_empty(bool sendNulls)
    {
        var collections = sendNulls
            ? """
              ,"countryIds":null,"regionIds":null,"categoryIds":null,
              "beneficiaryTypeIds":null,"projectTypeIds":null,"tagIds":null,"languages":null
              """
            : string.Empty;
        var json = $$"""
                     {
                       "name":"  Fundación Demo  ",
                       "homeCountryId":152,
                       "organizationTypeId":2,
                       "previousFundingExperience":0
                       {{collections}}
                     }
                     """;
        using var request = AuthenticatedPut(json);

        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Fundación Demo", repository.UpdatedProfile!.Name);
        Assert.Empty(repository.UpdatedProfile.CountryIds);
        Assert.Empty(repository.UpdatedProfile.RegionIds);
        Assert.Empty(repository.UpdatedProfile.CategoryIds);
        Assert.Empty(repository.UpdatedProfile.BeneficiaryTypeIds);
        Assert.Empty(repository.UpdatedProfile.ProjectTypeIds);
        Assert.Empty(repository.UpdatedProfile.TagIds);
        Assert.Empty(repository.UpdatedProfile.Languages);
        Assert.Empty(payload.RootElement.GetProperty("countryIds").EnumerateArray());
        Assert.Empty(payload.RootElement.GetProperty("languages").EnumerateArray());
    }

    [Fact]
    public async Task Put_profile_preserves_omitted_funding_experience_types_for_experienced_organization()
    {
        repository.ExistingFundingExperienceTypeIds = [1, 4];
        using var request = AuthenticatedPut("""
            {
              "name":"Fundación Demo",
              "homeCountryId":152,
              "organizationTypeId":2,
              "previousFundingExperience":2
            }
            """);

        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal([1, 4], repository.UpdatedProfile!.FundingExperienceTypeIds);
        Assert.Equal([1, 4], payload.RootElement.GetProperty("fundingExperienceTypeIds")
            .EnumerateArray().Select(value => value.GetInt16()).ToArray());
    }

    [Fact]
    public async Task Put_profile_treats_an_explicit_empty_funding_experience_list_as_clear()
    {
        repository.ExistingFundingExperienceTypeIds = [1, 4];
        using var request = AuthenticatedPut("""
            {
              "name":"Fundación Demo",
              "homeCountryId":152,
              "organizationTypeId":2,
              "previousFundingExperience":2,
              "fundingExperienceTypeIds":[]
            }
            """);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty(repository.UpdatedProfile!.FundingExperienceTypeIds!);
    }

    [Fact]
    public async Task Put_profile_clears_funding_experience_types_when_experience_is_no()
    {
        repository.ExistingFundingExperienceTypeIds = [1, 4];
        using var request = AuthenticatedPut("""
            {
              "name":"Fundación Demo",
              "homeCountryId":152,
              "organizationTypeId":2,
              "previousFundingExperience":1,
              "fundingExperienceTypeIds":[1,4]
            }
            """);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Empty(repository.UpdatedProfile!.FundingExperienceTypeIds!);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Put_profile_preserves_each_omitted_or_null_custom_taxonomy_dimension(bool sendNulls)
    {
        repository.ExistingCustomTaxonomyValues =
        [
            new(OrganizationCustomTaxonomyKind.ImpactArea, "Economía circular", "ECONOMIA CIRCULAR"),
            new(OrganizationCustomTaxonomyKind.Language, "Mapudungun", "MAPUDUNGUN")
        ];
        var custom = sendNulls
            ? """
              ,"customImpactAreas":null,"customBeneficiaryTypes":null,
              "customProjectTypes":null,"customLanguages":null
              """
            : string.Empty;
        using var request = AuthenticatedPut($$"""
            {
              "name":"Fundación Demo",
              "homeCountryId":152,
              "organizationTypeId":2,
              "previousFundingExperience":0
              {{custom}}
            }
            """);

        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(2, repository.UpdatedProfile!.CustomTaxonomyValues!.Count);
        Assert.Equal(["Economía circular"], payload.RootElement.GetProperty("customImpactAreas")
            .EnumerateArray().Select(value => value.GetString()!).ToArray());
        Assert.Equal(["Mapudungun"], payload.RootElement.GetProperty("customLanguages")
            .EnumerateArray().Select(value => value.GetString()!).ToArray());
        Assert.Empty(payload.RootElement.GetProperty("customBeneficiaryTypes").EnumerateArray());
        Assert.Empty(payload.RootElement.GetProperty("customProjectTypes").EnumerateArray());
    }

    [Fact]
    public async Task Put_profile_clears_only_explicit_empty_custom_dimension_and_preserves_omitted_ones()
    {
        repository.ExistingCustomTaxonomyValues =
        [
            new(OrganizationCustomTaxonomyKind.ImpactArea, "Economía circular", "ECONOMIA CIRCULAR"),
            new(OrganizationCustomTaxonomyKind.Language, "Mapudungun", "MAPUDUNGUN")
        ];
        using var request = AuthenticatedPut("""
            {
              "name":"Fundación Demo",
              "homeCountryId":152,
              "organizationTypeId":2,
              "previousFundingExperience":0,
              "customImpactAreas":[]
            }
            """);

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Collection(repository.UpdatedProfile!.CustomTaxonomyValues!, value =>
        {
            Assert.Equal(OrganizationCustomTaxonomyKind.Language, value.Kind);
            Assert.Equal("Mapudungun", value.Name);
        });
    }

    [Fact]
    public async Task Put_profile_reports_each_missing_required_field_without_calling_repository()
    {
        using var request = AuthenticatedPut("{}");

        using var response = await client.SendAsync(request);
        using var payload = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var errors = payload.RootElement.GetProperty("errors");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.True(errors.TryGetProperty("name", out _));
        Assert.True(errors.TryGetProperty("homeCountryId", out _));
        Assert.True(errors.TryGetProperty("organizationTypeId", out _));
        Assert.Equal(0, repository.UpdateCalls);
    }

    public void Dispose()
    {
        client.Dispose();
        application.Dispose();
    }

    private static HttpRequestMessage AuthenticatedPut(string json)
    {
        var request = new HttpRequestMessage(HttpMethod.Put, ProfilePath)
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", CreateJwt());
        request.Headers.TryAddWithoutValidation("If-Match", "\"0102030405060708\"");
        return request;
    }

    private static string CreateJwt()
    {
        var now = DateTime.UtcNow;
        return new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(
            JwtIssuer,
            JwtAudience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, UserId.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, UserId.ToString("D")),
                new Claim("auth_level", "full"),
                new Claim("amr", "pwd"),
                new Claim("auth_time", new DateTimeOffset(now).ToUnixTimeSeconds().ToString())
            ],
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(SigningKey), SecurityAlgorithms.HmacSha512)));
    }

    private sealed class StubRepository : IOrganizationRepository
    {
        public int UpdateCalls { get; private set; }
        public OrganizationProfileData? UpdatedProfile { get; private set; }
        public IReadOnlyList<short> ExistingFundingExperienceTypeIds { get; set; } = [];
        public IReadOnlyList<OrganizationCustomTaxonomyValue> ExistingCustomTaxonomyValues { get; set; } = [];
        private byte ProfileStatus { get; set; }
        private decimal ProfileCompleteness { get; set; }

        public Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken) =>
            Task.FromResult(new OrganizationCatalogs(
                [], [], [], [], [], [], [], [], [], [], [], [], [], []));

        public Task<IReadOnlyList<OrganizationSummary>> ListForUserAsync(
            Guid userPublicId, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<PersistedOrganization> CreateAsync(
            Guid userPublicId, OrganizationProfileData profile, string snapshotJson,
            byte[] contentHash, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<OrganizationProfile?> GetProfileAsync(
            Guid userPublicId, Guid organizationPublicId, CancellationToken cancellationToken)
        {
            if (organizationPublicId != OrganizationId)
                return Task.FromResult<OrganizationProfile?>(null);

            var profile = UpdatedProfile ?? new OrganizationProfileData(
                "Fundación Demo", null, null, 152, 2, null, null, null, null, null,
                ExistingFundingExperienceTypeIds.Count > 0 ? (byte)2 : (byte)0, null,
                null, null, null, null, null, null, [], [], [], [], [], [], [],
                ExistingFundingExperienceTypeIds, ExistingCustomTaxonomyValues);
            return Task.FromResult<OrganizationProfile?>(new OrganizationProfile(
                organizationPublicId, profile.Name, profile.LegalName, profile.TaxIdentifier,
                profile.HomeCountryId, profile.OrganizationTypeId, profile.LegalEntityTypeId,
                profile.OrganizationSizeId, profile.EstablishedYear, profile.WebsiteUrl,
                profile.Description, profile.PreviousFundingExperience, profile.ExperienceSummary,
                profile.AnnualBudgetMin, profile.AnnualBudgetMax, profile.AnnualBudgetCurrency,
                profile.DesiredFundingMin, profile.DesiredFundingMax, profile.DesiredFundingCurrency,
                ProfileStatus, ProfileCompleteness, 2, 1, [8, 7, 6, 5, 4, 3, 2, 1],
                profile.CountryIds, profile.RegionIds, profile.CategoryIds,
                profile.BeneficiaryTypeIds, profile.ProjectTypeIds, profile.TagIds,
                profile.Languages, profile.FundingExperienceTypeIds ?? [],
                profile.CustomTaxonomyValues ?? []));
        }

        public Task<PersistedOrganization> UpdateProfileAsync(
            Guid userPublicId, Guid organizationPublicId, byte[] expectedRowVersion,
            OrganizationProfileData profile, byte profileStatus, decimal profileCompleteness,
            string snapshotJson, byte[] contentHash, CancellationToken cancellationToken)
        {
            UpdateCalls++;
            UpdatedProfile = profile;
            ProfileStatus = profileStatus;
            ProfileCompleteness = profileCompleteness;
            return Task.FromResult(new PersistedOrganization(
                organizationPublicId, 2, [8, 7, 6, 5, 4, 3, 2, 1]));
        }
    }
}
