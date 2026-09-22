using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingTranslationTests
{
    [Theory]
    [InlineData("es", true)] [InlineData("en", true)] [InlineData("es-CL", false)]
    [InlineData("ES", false)] [InlineData("fr", false)] [InlineData(null, false)]
    public void Only_explicit_supported_languages(string? language, bool expected) =>
        Assert.Equal(expected, FundingTranslationRules.Supports(language));

    [Fact]
    public void Draft_can_be_incomplete_but_review_must_match_source_coverage()
    {
        var original = new FundingTranslationText("Title", "Summary", "Description");
        var text = new FundingTranslationText("Título", null, "Descripción", Requirements: "Invented");
        Assert.Empty(FundingTranslationRules.Validate(new(1, 0, false, text), original));
        var errors = FundingTranslationRules.Validate(new(1, 0, true, text), original);
        Assert.Equal(2, errors.Count);
        Assert.NotEmpty(FundingTranslationRules.Validate(new(0, -1, false, null), original));
        Assert.NotEmpty(FundingTranslationRules.Validate(new(1, 0, false, new(Title: new string('x', 351))), original));
        Assert.Equal(new FundingTranslationText("Hola"), FundingTranslationRules.Normalize(new(" Hola ", " \t")));
    }

    [Theory]
    [InlineData(false, true, 3, "es", 0, "Original")]
    [InlineData(true, false, 3, "es", 1, "Original")]
    [InlineData(true, true, 2, "es", 1, "Original")]
    [InlineData(true, true, 3, "en", 1, "Original")]
    [InlineData(true, true, 3, "es", 1, "Traducido")]
    public async Task Only_current_reviewed_matching_language_is_used(bool enabled, bool reviewed, int version, string storedLanguage, int calls, string title)
    {
        var repository = new FakeRepository { Value = new(storedLanguage, version, 7, reviewed, new("Traducido", "Resumen", "Descripción"), DateTimeOffset.UtcNow) };
        var service = new FundingTranslationService(repository, new() { Enabled = enabled });
        var original = Original();
        var result = await service.LocalizeAsync(original, "es", default);
        Assert.Equal(title, result.Title);
        Assert.Equal(calls, repository.Calls);
        Assert.Equal(original.Currency, result.Currency);
        Assert.Equal(original.MinimumAmount, result.MinimumAmount);
        Assert.Equal(original.MaximumAmount, result.MaximumAmount);
        Assert.Equal(original.CloseDate, result.CloseDate);
        Assert.Equal(original.ApplicationUrl, result.ApplicationUrl);
        Assert.Equal(original.SourceUrl, result.SourceUrl);
        Assert.Equal(original.SponsorName, result.SponsorName);
        Assert.Equal(original.ExternalId, result.ExternalId);
        Assert.Equal("Original", original.Title);
    }

    [Fact]
    public async Task Original_request_does_not_read_translation_storage()
    {
        var repository = new FakeRepository();
        var service = new FundingTranslationService(repository, new() { Enabled = true });
        Assert.Same(OriginalInstance, await service.LocalizeAsync(OriginalInstance, null, default));
        Assert.Equal(0, repository.Calls);
        var fallback = await service.LocalizeAsync(OriginalInstance, "es", default);
        Assert.Equal("original", fallback.Localization?.Status);
        Assert.Equal(OriginalInstance.Title, fallback.Title);
    }

    private static readonly FundingOpportunityDetails OriginalInstance = Original();
    private static FundingOpportunityDetails Original() => new(Guid.NewGuid(), "original", "Original", "Description", "Summary",
        "Sponsor", "https://example.invalid", "https://example.invalid/apply", "AUD", 100, 200,
        new(2026, 1, 1), new(2027, 1, 1), null, null, null, false, "Source", "https://example.invalid/source",
        "REF-1", DateTimeOffset.UtcNow, 100, [], 3);

    private sealed class FakeRepository : IFundingTranslationRepository
    {
        public Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token) => throw new NotSupportedException();
        public FundingTranslation? Value { get; init; }
        public int Calls { get; private set; }
        public Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int version, CancellationToken token)
        { Calls++; return Task.FromResult(Value); }
        public Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token) => throw new NotSupportedException();
        public Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data, byte[] rowVersion, CancellationToken token) => throw new NotSupportedException();
    }

    [Fact]
    public void Translation_field_joins_use_explicit_binary_collation_independent_of_database_default()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var sql = string.Join('\n', SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 53).Batches);
        Assert.Contains("Name NVARCHAR(100) COLLATE Latin1_General_100_BIN2 PRIMARY KEY", sql);
        Assert.Contains("s.[key] COLLATE Latin1_General_100_BIN2 = f.Name", sql);
        Assert.Contains("t.[key] COLLATE Latin1_General_100_BIN2 = f.Name", sql);
        Assert.DoesNotContain("s.[key] = f.Name", sql);
        Assert.DoesNotContain("t.[key] = f.Name", sql);
    }

    [Fact]
    public void Existing_asset_smokes_account_for_exact_translation_grants_without_changing_worker_permissions()
    {
        var root = SolutionRootLocator.Find();
        foreach (var sequence in new[] { 37, 38 })
        {
            var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == sequence);
            var sql = string.Join('\n', smoke.Batches);
            Assert.Contains("OBJECT_ID(N'dbo.FundingPlatform_FundingTranslations', N'U') IS NULL THEN 0 ELSE 3 END", sql);
            Assert.Contains("OBJECT_ID(N'dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries', N'P') IS NULL THEN 0 ELSE 1 END", sql);
            Assert.Contains("WHERE grantee_principal_id = @WorkerRoleId) <> 53 +", sql);
            foreach (var batch in smoke.Batches)
            {
                new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
                Assert.Empty(errors);
            }
        }
        var manifest = string.Join('\n', SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 27).Batches);
        foreach (var procedure in new[] { "AdminGet", "Read", "Save", "ReadSummaries" })
            Assert.Contains("FundingPlatform_usp_FundingTranslation_" + procedure, manifest);
    }

    [Fact]
    public void Migration_and_smoke_parse_and_enforce_versions_and_public_readiness()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(s => s.Sequence == 53);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(s => s.Sequence == 53);
        var parser = new TSql170Parser(true, SqlEngineType.SqlAzure);
        foreach (var batch in migration.Batches.Concat(smoke.Batches))
        {
            using var reader = new StringReader(batch);
            _ = parser.Parse(reader, out var errors);
            Assert.Empty(errors);
        }
        var sql = string.Join('\n', migration.Batches);
        Assert.Contains("t.SourceContentVersion = o.ContentVersion", sql);
        Assert.Contains("t.Reviewed = 1", sql);
        Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", sql);
        Assert.Contains("FundingPlatform_usp_AdminActor_Lock", sql);
        Assert.Contains("UPDLOCK,HOLDLOCK", sql);
        Assert.Contains("@CurrentRowVersion <> @SourceRowVersion", sql);
        Assert.Contains("INSERT dbo.FundingPlatform_FundingTranslationHistory", sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
    }
}
