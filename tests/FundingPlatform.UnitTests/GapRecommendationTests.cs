using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class GapRecommendationTests
{
    private static readonly Guid Actor = Guid.NewGuid();
    private static readonly GapRecommendationRequest Request = new(Guid.NewGuid(), Guid.NewGuid());
    private static GapRecommendationContext Context() => new("Project", "Fund", 4, 152, 4, true, true,
        "https://example.invalid/terms", "Municipios", "Consultoría GIS", true, DateTimeOffset.UtcNow);
    private static DiscoveryFeatures Features(int[]? countries = null, int[]? categories = null, string[]? skills = null)
        => new(countries ?? [152], categories ?? [1], [], null, null, null, Skills: skills);
    private static DiscoveryCandidate Candidate(int country = 250, int[]? categories = null, string[]? skills = null, Guid? id = null)
        => new(id ?? Guid.NewGuid(), "Candidate", null, "/profile", Features([country], categories, skills));
    private static DiscoveryMatchingContext Directory(params DiscoveryCandidate[] candidates)
        => new("Project", Features([250]) with { Needs = "Consultoría GIS" }, candidates, candidates.Length, DateTimeOffset.UtcNow);

    [Fact]
    public async Task Requirements_have_distinct_origins_and_use_home_country_not_project_footprint()
    {
        var foreign = Candidate(250, skills: ["GIS"]);
        var local = Candidate(152, skills: ["GIS"]);
        var repository = new Repository(Context(), Directory(foreign, local));
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        Assert.Equal(4, result!.Items.Count);
        var international = result.Items.Single(i => i.Code == "international-partner");
        Assert.Equal(foreign.Id, Assert.Single(international.Candidates).Id);
        Assert.Equal(["funding"], international.Origins);
        Assert.Equal(["funding", "project"], result.Items.Single(i => i.Code == "consortium").Origins);
        Assert.Equal(["project"], result.Items.Single(i => i.Code == "professionals").Origins);
        Assert.Equal(2, repository.DiscoveryCalls); // Not one expensive directory query per card.
        Assert.Equal(Actor, repository.Actor);
        Assert.All(repository.Requests, r => { Assert.Equal(Request.ProjectId, r.SourceId); Assert.Equal(DiscoverySubjectKind.Project, r.SourceKind); });
    }

    [Theory]
    [InlineData(null)]
    [InlineData(3)]
    public async Task Unreviewed_or_stale_funding_does_not_drive_requirements_or_expose_evidence(int? version)
    {
        var repository = new Repository(Context() with { ReviewedContentVersion = version, SeekingConsortium = false }, Directory(Candidate(skills: ["GIS"])));
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        Assert.False(result!.ClassificationCurrent); Assert.Null(result.EvidenceUrl);
        Assert.Equal(["partners", "professionals"], result.Items.Select(i => i.Code));
        Assert.All(result.Items, i => Assert.Equal(["project"], i.Origins));
    }

    [Fact]
    public async Task No_needs_means_no_directory_requests_and_not_an_eligibility_claim()
    {
        var repository = new Repository(Context() with { RequiresConsortium = false, RequiresInternationalPartner = false,
            SoughtPartners = " ", SoughtProfessionals = null, SeekingConsortium = null }, Directory());
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        Assert.Empty(result!.Items); Assert.Equal(0, repository.DiscoveryCalls);
    }

    [Fact]
    public async Task Missing_home_country_blocks_international_suggestions()
    {
        var repository = new Repository(Context() with { HomeCountryId = null }, Directory(Candidate()));
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        var item = result!.Items.Single(i => i.Code == "international-partner");
        Assert.Empty(item.Candidates); Assert.Equal("missing-home-country", item.State);
    }

    [Fact]
    public async Task Unknown_or_ambiguous_candidate_country_is_not_international_evidence()
    {
        var unknown = Candidate() with { Features = Features([]) };
        var ambiguous = Candidate() with { Features = Features([250, 152]) };
        var repository = new Repository(Context(), Directory(unknown, ambiguous));
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        Assert.Empty(result!.Items.Single(i => i.Code == "international-partner").Candidates);
    }

    [Fact]
    public async Task Other_and_unmatched_categories_cannot_justify_partner_suggestions()
    {
        var directory = Directory(Candidate(categories: [16]), Candidate(categories: [2])) with { Source = Features(categories: [1, 16]) };
        var repository = new Repository(Context(), directory);
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        Assert.All(result!.Items, item => { Assert.Empty(item.Candidates); Assert.Equal("no-evidence", item.State); });
    }

    [Fact]
    public async Task Professional_requires_skill_evidence_not_sector_only_and_preserves_accent_normalization()
    {
        var skilled = Candidate(categories: [2], skills: ["Consultoria"]);
        var sectorOnly = Candidate(skills: ["Contabilidad"]);
        var repository = new Repository(Context(), Directory(skilled, sectorOnly));
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        var candidate = Assert.Single(result!.Items.Single(i => i.Code == "professionals").Candidates);
        Assert.Equal(skilled.Id, candidate.Id); Assert.Equal(["consultoria"], candidate.SharedSkills);
    }

    [Fact]
    public async Task Suggestions_are_bounded_deterministic_and_explicit_about_the_sample()
    {
        var candidates = Enumerable.Range(1, 201).Select(index => Candidate(id: new Guid(index, 0, 0, new byte[8]))).Reverse().ToArray();
        var directory = Directory(candidates) with { TotalCandidateCount = 700 };
        var repository = new Repository(Context(), directory);
        var result = await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default);
        var item = result!.Items.Single(i => i.Code == "international-partner");
        Assert.Equal(3, item.Candidates.Count); Assert.Equal(200, item.EvaluatedCandidateCount);
        Assert.Equal(700, item.TotalCandidateCount); Assert.True(item.IsTruncated);
        Assert.Equal(candidates.Take(200).OrderBy(c => c.Id).Take(3).Select(c => c.Id), item.Candidates.Select(c => c.Id));
    }

    [Fact]
    public async Task Denied_context_never_queries_candidates()
    {
        var repository = new Repository(null, Directory(Candidate()));
        Assert.Null(await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default));
        Assert.Equal(0, repository.DiscoveryCalls);
    }

    [Fact]
    public async Task Revoked_membership_during_directory_read_is_not_an_empty_success()
    {
        var repository = new Repository(Context(), null);
        Assert.Null(await new GapRecommendationService(repository, repository).ReadAsync(Actor, Request, default));
        Assert.Equal(1, repository.DiscoveryCalls);
    }

    [Fact]
    public async Task Invalid_identifiers_fail_before_database_access()
    {
        var repository = new Repository(Context(), Directory());
        var service = new GapRecommendationService(repository, repository);
        Assert.Equal(2, GapRecommendationService.Validate(new(Guid.Empty, Guid.Empty)).Count);
        await Assert.ThrowsAsync<ArgumentException>(() => service.ReadAsync(Actor, Request with { ProjectId = Guid.Empty }, default));
        await Assert.ThrowsAsync<ArgumentException>(() => service.ReadAsync(Guid.Empty, Request, default));
        Assert.Equal(0, repository.ContextCalls);
    }

    [Fact]
    public void New_migration_is_parseable_and_read_only_with_tenant_public_and_version_guards()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var script = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 50);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 50);
        foreach (var batch in script.Batches.Concat(smoke.Batches))
        {
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
            Assert.Empty(errors);
        }
        var sql = string.Join("\n", script.Batches);
        Assert.Contains("membership.UserId = @UserId AND membership.MembershipStatus = 1", sql);
        Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", sql);
        Assert.Contains("metadata.ContentVersion = opportunity.ContentVersion", sql);
        Assert.DoesNotContain("INSERT dbo.", sql); Assert.DoesNotContain("UPDATE dbo.", sql);
        Assert.DoesNotContain("GRANT SELECT", sql); Assert.DoesNotContain("CREATE TABLE", sql);
        foreach (var sequence in new[] { 27, 37, 38 })
            Assert.Contains("FundingPlatform_usp_GapRecommendations_Context", string.Join("\n",
                SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == sequence).Batches));
    }

    private sealed class Repository(GapRecommendationContext? context, DiscoveryMatchingContext? directory)
        : IGapRecommendationRepository, IDiscoveryMatchingRepository
    {
        public int ContextCalls, DiscoveryCalls; public Guid Actor;
        public List<DiscoveryMatchingRequest> Requests { get; } = [];
        public Task<GapRecommendationContext?> ReadAsync(Guid userId, GapRecommendationRequest request, CancellationToken token)
        { ContextCalls++; Actor = userId; Assert.Equal(Request, request); return Task.FromResult(context); }
        public Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token)
        { DiscoveryCalls++; Assert.Equal(Actor, userId); Requests.Add(request); return Task.FromResult(directory); }
    }
}
