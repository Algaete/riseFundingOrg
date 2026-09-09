using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;
public sealed class DiscoveryMatchingTests
{
    private static DiscoveryFeatures Facts(int[]? countries = null, int[]? categories = null, string? currency = null, decimal? amount = null)
        => new(countries ?? [], categories ?? [], [], amount, amount, currency);
    [Fact]
    public void Unknown_inputs_never_manufacture_a_score_or_evidence()
    {
        var match = DiscoveryMatchingService.Evaluate(Facts(), new(Guid.NewGuid(), "Project", null, "/marketplace", Facts()), DiscoveryTargetKind.Projects);
        Assert.Null(match.Score); Assert.Equal(0, match.EvidenceCoverage);
        Assert.Equal("insufficient-data", match.Classification);
        Assert.Contains(match.Reasons, rule => rule.Code == "official-eligibility" && rule.Outcome == "verify");
    }
    [Fact]
    public void Currency_difference_is_unknown_not_conversion_or_budget_alignment()
    {
        var result = DiscoveryMatchingService.Evaluate(Facts([152], [1], "USD", 100), new(Guid.NewGuid(), "Project", null, "/", Facts([152], [1], "CLP", 100)), DiscoveryTargetKind.Projects);
        Assert.Contains(result.Reasons, rule => rule.Code == "amount" && rule.Outcome == "currency-mismatch");
        Assert.Equal(60, result.EvidenceCoverage); Assert.Equal(60, result.Score);
    }
    [Fact]
    public void Explicit_organization_exclusions_take_precedence_over_inclusions()
    {
        var expected = Facts([152], [1]) with { OrganizationTypes = [2], ExcludedOrganizationTypes = [2] };
        var actual = Facts([152], [1]) with { OrganizationTypes = [2] };
        var result = DiscoveryMatchingService.Evaluate(expected, new(Guid.NewGuid(), "Project", null, "/", actual), DiscoveryTargetKind.Projects);
        Assert.Contains(result.Reasons, rule => rule.Code == "organization-type" && rule.Outcome == "gap");
        Assert.Equal("gaps", result.Classification);
    }
    [Fact]
    public void Professional_skills_are_evidence_not_automatic_participation()
    {
        var source = Facts([152], [1]) with { Needs = "Consultoría GIS para agua" };
        var candidate = Facts([152], [1]) with { Skills = ["GIS", "Datos"] };
        var result = DiscoveryMatchingService.Evaluate(source, new(Guid.NewGuid(), "Professional", null, "/professionals", candidate), DiscoveryTargetKind.Professionals);
        Assert.Contains(result.Reasons, rule => rule.Code == "skills" && rule.Outcome == "match" && rule.Evidence.Contains("gis"));
        Assert.Contains(result.Reasons, rule => rule.Code == "availability" && rule.Outcome == "verify");
    }
    [Theory]
    [InlineData("Consultoría", "consultoria")]
    [InlineData("investigación social", "Investigacion")]
    public void Accents_do_not_split_skill_words(string needs, string skill)
    {
        var result = DiscoveryMatchingService.Evaluate(Facts() with { Needs = needs }, new(Guid.NewGuid(), "Professional", null, "/", Facts() with { Skills = [skill] }), DiscoveryTargetKind.Professionals);
        Assert.Contains(result.Reasons, rule => rule.Code == "skills" && rule.Outcome == "match");
    }
    [Fact]
    public void Other_is_not_an_area_of_compatibility()
    {
        var result = DiscoveryMatchingService.Evaluate(Facts(categories: [16]), new(Guid.NewGuid(), "Other", null, "/", Facts(categories: [16])), DiscoveryTargetKind.Organizations);
        Assert.Null(result.Score);
    }
    [Theory]
    [InlineData(1,1)]
    [InlineData(2,1)]
    [InlineData(3,2)]
    [InlineData(4,3)]
    [InlineData(9,1)]
    public void Invalid_direction_is_rejected(byte source, byte target)
        => Assert.NotEmpty(DiscoveryMatchingService.Validate(new((DiscoverySubjectKind)source, Guid.NewGuid(), (DiscoveryTargetKind)target)));
    [Fact]
    public async Task Funder_country_is_not_funding_eligibility_and_corpus_truncation_is_reported()
    {
        var source = Facts([152], [1], "USD", 100);
        var repository = new Repository(new("Funder", source, [new(Guid.NewGuid(), "Project", null, "/", source)], 300, DateTimeOffset.UtcNow));
        var service = new DiscoveryMatchingService(repository);
        var request = new DiscoveryMatchingRequest(DiscoverySubjectKind.Funder, Guid.NewGuid(), DiscoveryTargetKind.Projects);
        var page = await service.SearchAsync(Guid.NewGuid(), request, default);
        Assert.Null(Assert.Single(page!.Items).Score);
        Assert.True(page.IsTruncated); Assert.Equal(300, page.TotalCandidateCount);
        page = await service.SearchAsync(Guid.NewGuid(), request with { Criteria = new(152, 1, 50, 150, "USD") }, default);
        Assert.Equal(80, Assert.Single(page!.Items).Score);
    }
    [Fact]
    public void Sql_is_read_only_tenant_bound_and_uses_public_projection_and_optin()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 44);
        foreach (var batch in script.Batches)
        {
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(e => e.Message)));
        }
        var sql = string.Join("\n", script.Batches);
        Assert.Contains("owners.UserId = @UserId AND owners.IsActive = 1", sql);
        Assert.Contains("m.MembershipStatus = 1", sql);
        Assert.Contains("profiles.IsDiscoverable = 1 AND profiles.AllowsInvitations = 1", sql);
        Assert.Contains("FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
        Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", sql);
        Assert.Contains("TOP(200)", sql); Assert.Contains("blocked.Status = 4", sql);
        Assert.DoesNotContain("INSERT INTO dbo.", sql); Assert.DoesNotContain("UPDATE dbo.", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
    }
    private sealed class Repository(DiscoveryMatchingContext context) : IDiscoveryMatchingRepository
    {
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token) => Task.FromResult<DiscoveryMatchingContext?>(context);
    }
}
