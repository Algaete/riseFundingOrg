using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class PartnerGeographyTests
{
    private static PartnerGeography Geography(string region = "EU", params int[] countries) =>
        new(PartnerGeographyScope.Specific, countries, [region], PartnerGeographyCatalog.Version);
    private static GapRecommendationContext Context(PartnerGeography? geography) => new("Project", "Fund", 2, 152, 2,
        false, true, "https://example.invalid/terms", null, null, false, DateTimeOffset.UtcNow, geography,
        geography is null ? [] : geography.CountryIds.Concat(PartnerGeographyCatalog.Regions.Where(r => geography.RegionCodes.Contains(r.Code))
            .SelectMany(r => r.CountryIds)).Distinct().ToArray());
    private static DiscoveryFeatures Features(int[] countries, string[]? skills = null) => new(countries, [1], [], null, null, null, Skills: skills);
    private static DiscoveryCandidate Candidate(int country) => new(Guid.NewGuid(), $"Country {country}", null, "/profile", Features(country > 0 ? [country] : [], ["GIS"]));

    [Theory]
    [InlineData("EU", 250, true)] [InlineData("EU", 826, false)] [InlineData("EU", 756, false)]
    [InlineData("EU", 196, true)] [InlineData("M49-150", 826, true)] [InlineData("M49-150", 756, true)]
    [InlineData("M49-150", 196, false)] [InlineData("EU", 840, false)] [InlineData("EU", 0, false)]
    [InlineData("M49-419", 152, true)] [InlineData("M49-419", 840, false)]
    public async Task Regional_groups_mean_exact_headquarters_membership(string region, int country, bool expected)
    {
        var context = Context(Geography(region)) with { RequiresInternationalPartner = false, SoughtPartners = "Partners" };
        var result = await Read(context, Candidate(country));
        Assert.Equal("specific", result.GeographyState);
        Assert.Equal(expected ? 1 : 0, Assert.Single(result.Items).Candidates.Count);
    }

    [Fact]
    public async Task Explicit_countries_union_with_regions_but_international_still_excludes_applicant_home()
    {
        var result = await Read(Context(Geography("EU", 826)) with { HomeCountryId = 250 }, Candidate(250), Candidate(826), Candidate(196), Candidate(840));
        Assert.Equal(new[] { 196, 826 }, Assert.Single(result.Items).Candidates.Select(c => c.HomeCountryId!.Value).Order());
    }

    [Fact]
    public async Task Country_only_selection_and_new_standalone_geography_card_work_without_inventing_a_required_partner()
    {
        var context = Context(new(PartnerGeographyScope.Specific, [826], [])) with { RequiresInternationalPartner = false };
        var result = await Read(context, Candidate(250), Candidate(826));
        var item = Assert.Single(result.Items);
        Assert.Equal("partner-geography", item.Code); Assert.Equal(826, Assert.Single(item.Candidates).HomeCountryId);
    }

    [Theory]
    [InlineData(null)] [InlineData(1)]
    public async Task Stale_or_absent_editorial_review_cannot_restrict_project_partner_needs(int? version)
    {
        var result = await Read(Context(Geography()) with { ReviewedContentVersion = version, SoughtPartners = "Partners" }, Candidate(840));
        Assert.Equal("unverified", result.GeographyState); Assert.Null(result.PartnerGeography); Assert.Null(result.EvidenceUrl);
        Assert.Equal(840, Assert.Single(Assert.Single(result.Items).Candidates).HomeCountryId);
    }

    [Theory]
    [InlineData(0)] [InlineData(1)]
    public async Task Unknown_is_not_global_and_explicit_unrestricted_still_requires_a_foreign_headquarters(int scope)
    {
        var result = await Read(Context(new((PartnerGeographyScope)scope, [], [])), Candidate(152), Candidate(840));
        Assert.Equal(scope == 0 ? "unverified" : "any", result.GeographyState);
        Assert.Equal(840, Assert.Single(Assert.Single(result.Items).Candidates).HomeCountryId);
    }

    [Theory]
    [InlineData("catalog")] [InlineData("inactive")] [InlineData("unresolved")] [InlineData("unknown-group")]
    public async Task Invalid_geography_fails_closed_but_does_not_filter_individual_professionals(string reason)
    {
        var context = Context(Geography()) with { SoughtProfessionals = "GIS" };
        context = reason switch {
            "catalog" => context with { PartnerGeography = Geography() with { CatalogVersion = "old" } },
            "inactive" => context with { PartnerGeographyValid = false },
            "unresolved" => context with { EligiblePartnerCountryIds = null },
            _ => context with { PartnerGeography = Geography("Schengen") }
        };
        var result = await Read(context, Candidate(840));
        Assert.Equal("needs-review", result.GeographyState);
        var organization = result.Items.Single(i => i.Code == "international-partner");
        Assert.Empty(organization.Candidates); Assert.Equal("geography-needs-review", organization.State);
        Assert.Single(result.Items.Single(i => i.Code == "professionals").Candidates);
    }

    [Fact]
    public async Task Active_country_expansion_is_authoritative_and_unknown_headquarters_never_match()
    {
        var result = await Read(Context(Geography()) with { EligiblePartnerCountryIds = [] }, Candidate(250), Candidate(0));
        Assert.Empty(Assert.Single(result.Items).Candidates);
    }

    [Fact]
    public void Classification_rejects_empty_specific_duplicate_unknown_null_and_stale_selections()
    {
        PartnerGeography[] invalid = [new(PartnerGeographyScope.Specific, [], []), new(PartnerGeographyScope.Any, [250], []),
            new(PartnerGeographyScope.Unknown, [], ["EU"]), Geography("eu"), Geography("EU") with { CatalogVersion = null },
            Geography("EU", 250, 250), Geography("EU") with { RegionCodes = ["EU", "EU"] },
            new(PartnerGeographyScope.Specific, null!, []), new(PartnerGeographyScope.Specific, [250], null!),
            Geography("EU", -1), Geography("EU") with { Scope = (PartnerGeographyScope)99 }];
        foreach (var geography in invalid)
            Assert.NotEmpty(FundingDiscoveryRules.Validate(new FundingDiscoveryReview(2, new(1, true, true, "https://example.invalid/terms", geography))));
        Assert.Empty(FundingDiscoveryRules.Validate(new FundingDiscoveryReview(2, new(1, true, true, "https://example.invalid/terms", Geography()))));
    }

    [Fact]
    public void Sql_and_application_share_an_exact_pinned_catalog_and_preserve_review_security()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 51);
        var sql = string.Join("\n", migration.Batches);
        var start = sql.IndexOf("FROM OPENJSON(N'", StringComparison.Ordinal) + "FROM OPENJSON(N'".Length;
        var json = sql[start..sql.IndexOf("')", start, StringComparison.Ordinal)];
        Assert.Equal(JsonSerializer.Serialize(PartnerGeographyCatalog.Regions, JsonSerializerOptions.Web), json);
        Assert.Equal(27, PartnerGeographyCatalog.Regions.Single(r => r.Code == "EU").CountryIds.Count);
        Assert.All(PartnerGeographyCatalog.Regions, region => Assert.Equal(region.CountryIds.Count, region.CountryIds.Distinct().Count()));
        foreach (var batch in migration.Batches.Concat(SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 51).Batches))
        { _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors); Assert.Empty(errors); }
        foreach (var guard in new[] { "FundingPlatform_usp_AdminActor_Lock", "@PreviousHash <> @RequestHash", "@PreviousVersion <> @ExpectedVersion",
            "ContentVersion = @ContentVersion", "metadata.ContentVersion = opportunity.ContentVersion", "c.IsActive = 1", "FundingPlatform_ifn_FundingOpportunityPublicReady" })
            Assert.Contains(guard, sql);
        Assert.DoesNotContain("GRANT ", sql); Assert.DoesNotContain("CREATE TABLE", sql);
    }

    private static async Task<GapRecommendationResult> Read(GapRecommendationContext context, params DiscoveryCandidate[] candidates)
    {
        var repository = new Repository(context, candidates);
        return (await new GapRecommendationService(repository, repository).ReadAsync(Guid.NewGuid(), new(Guid.NewGuid(), Guid.NewGuid()), default))!;
    }
    private sealed class Repository(GapRecommendationContext context, DiscoveryCandidate[] candidates) : IGapRecommendationRepository, IDiscoveryMatchingRepository
    {
        public Task<GapRecommendationContext?> ReadAsync(Guid actor, GapRecommendationRequest request, CancellationToken token) => Task.FromResult<GapRecommendationContext?>(context);
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid actor, DiscoveryMatchingRequest request, CancellationToken token) =>
            Task.FromResult<DiscoveryMatchingContext?>(new("Project", Features([840]), candidates, candidates.Length, DateTimeOffset.UtcNow));
    }
}
