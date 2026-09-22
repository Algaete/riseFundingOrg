using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingTranslationListTests
{
    private static readonly Guid Id = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
    private static FundingOpportunitySummary Item() => new(Id, "original", "Original", "Summary", "Sponsor",
        "AUD", 100, 200, null, new(2027,1,1), "Source", "https://example.invalid", DateTimeOffset.UtcNow, 90,
        "nature-v1", 3);
    private static FundingSummaryTranslation Text() => new(Id, "es", 3, 7, true, "Traducido", "Resumen");

    [Theory]
    [InlineData(false, "es", 3, 0)]
    [InlineData(true, null, 3, 0)]
    [InlineData(true, "es", 0, 0)]
    [InlineData(true, "es", 3, 1)]
    public async Task Only_enabled_versioned_localized_pages_read_storage(bool enabled, string? language, int version, int calls)
    {
        var repo = new Repository { Items = [Text()] };
        var service = new FundingTranslationService(repo, new() { Enabled = enabled });
        var page = new FundingOpportunityPage([Item() with { ContentVersion = version }], 91, 3, 20);
        var result = await service.LocalizeAsync(page, language, default);
        Assert.Equal(calls, repo.Calls);
        Assert.Equal(91, result.TotalCount);
        Assert.Equal(3, result.PageNumber);
        Assert.Equal(20, result.PageSize);
        Assert.Equal(calls == 1 ? "Traducido" : "Original", result.Items[0].Title);
        Assert.Equal("Original", page.Items[0].Title);
        Assert.Equal(page.Items[0] with { Title = result.Items[0].Title, Summary = result.Items[0].Summary,
            Localization = result.Items[0].Localization }, result.Items[0]);
        if (!enabled || language is null) Assert.Same(page.Items, result.Items);
    }

    [Theory]
    [InlineData("draft")][InlineData("version")][InlineData("language")][InlineData("id")]
    [InlineData("title")][InlineData("summary")][InlineData("duplicate")][InlineData("revision")]
    public async Task Unreviewed_stale_incomplete_or_unrelated_values_never_replace_original(string kind)
    {
        var value = kind switch
        {
            "draft" => Text() with { Reviewed = false }, "version" => Text() with { SourceContentVersion = 2 },
            "language" => Text() with { Language = "en" }, "id" => Text() with { OpportunityId = Guid.NewGuid() },
            "title" => Text() with { Title = " " }, "summary" => Text() with { Summary = null },
            "revision" => Text() with { Revision = 0 }, _ => Text()
        };
        var repo = new Repository { Items = kind == "duplicate" ? [value, value] : [value] };
        var service = new FundingTranslationService(repo, new() { Enabled = true });
        var result = await service.LocalizeAsync(new FundingOpportunityPage([Item()], 1, 1, 12), "es", default);
        Assert.Equal("Original", result.Items[0].Title);
        Assert.Equal("Summary", result.Items[0].Summary);
        Assert.Equal("original", result.Items[0].Localization?.Status);
    }

    [Fact]
    public async Task Page_is_one_bounded_read_preserving_order_with_mixed_translation_availability()
    {
        var repo = new Repository { Items = [Text()] };
        var items = Enumerable.Range(0,50).Select(_ => Item() with { PublicId = Guid.NewGuid() }).ToArray();
        items[20] = Item();
        var service = new FundingTranslationService(repo, new() { Enabled = true });
        var result = await service.LocalizeAsync(new FundingOpportunityPage(items, 500, 2, 50), "es", default);
        Assert.Equal(1, repo.Calls);
        Assert.Equal(50, repo.References!.Count);
        Assert.Equal(items.Select(x => x.PublicId), result.Items.Select(x => x.PublicId));
        Assert.Single(result.Items, x => x.Localization?.Status == "translated");
        Assert.Equal("Traducido", result.Items[20].Title);
        await service.LocalizeAsync(new FundingOpportunityPage([], 0, 1, 50), "es", default);
        Assert.Equal(1, repo.Calls);
        await Assert.ThrowsAsync<ArgumentException>(() => service.LocalizeAsync(new FundingOpportunityPage(items, 50, 1, 50), "fr", default));
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() => service.LocalizeAsync(new FundingOpportunityPage(Enumerable.Repeat(Item(),101).ToArray(),101,1,101), "es", default));
        Assert.Equal(1, repo.Calls);
    }

    [Fact]
    public void Sql_batch_and_transactional_smoke_parse_and_keep_publication_and_version_guards()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(x => x.Sequence == 57);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(x => x.Sequence == 57);
        foreach (var batch in migration.Batches.Concat(smoke.Batches))
        {
            using var reader = new StringReader(batch);
            new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(x => x.Message)));
        }
        var sql = string.Join('\n', migration.Batches);
        foreach (var guard in new[] { "t.SourceContentVersion = o.ContentVersion", "o.ContentVersion = r.SourceContentVersion",
            "t.Reviewed = 1", "FundingPlatform_ifn_FundingOpportunityPublicReady()", "WITH EXECUTE AS OWNER",
            "DATALENGTH(@ReferencesJson) > 40000", "COUNT(*) FROM OPENJSON(@ReferencesJson)) > 100" }) Assert.Contains(guard, sql);
        Assert.DoesNotContain("GRANT SELECT", sql);
        Assert.Contains("ROLLBACK TRANSACTION", string.Join('\n', smoke.Batches));
    }

    private sealed class Repository : IFundingTranslationRepository
    {
        public int Calls { get; private set; }
        public IReadOnlyList<FundingTranslationReference>? References { get; private set; }
        public IReadOnlyList<FundingSummaryTranslation> Items { get; init; } = [];
        public Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token)
        { Calls++; References = references; return Task.FromResult(Items); }
        public Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token) => throw new NotSupportedException();
        public Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int version, CancellationToken token) => throw new NotSupportedException();
        public Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data, byte[] version, CancellationToken token) => throw new NotSupportedException();
    }
}
