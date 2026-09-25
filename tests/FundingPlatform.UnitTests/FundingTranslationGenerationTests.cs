using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingTranslationGenerationTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 22, 12, 0, 0, TimeSpan.Zero);
    private static readonly FundingTranslationText Source = new("Original", "Summary", "Description");
    private static readonly FundingTranslationText Translated = new("Título", "Resumen", "Descripción");
    private static FundingTranslationGenerationOptions Approved => new()
    {
        Enabled = true, ExternalProcessingApproved = true, ApprovalExpiresAtUtc = Now.AddDays(1),
        Model = "test-model-snapshot", InputUsdPerMillionTokens = 1, OutputUsdPerMillionTokens = 2,
        MaximumCostUsdPerRequest = 0.1m, MonthlyBudgetUsd = 1, MonthlyRequestLimit = 10
    };

    [Fact]
    public void Approval_requires_expiry_prices_and_bounded_budget_without_paid_defaults()
    {
        Assert.True(Approved.IsApproved(Now));
        foreach (var invalid in new[]
        {
            new FundingTranslationGenerationOptions(), Approved with { Enabled = false },
            Approved with { ExternalProcessingApproved = false }, Approved with { ApprovalExpiresAtUtc = Now },
            Approved with { Model = "" }, Approved with { Model = "wrong/model" },
            Approved with { MaximumCostUsdPerRequest = 0.01m }, Approved with { MaximumCostUsdPerRequest = 0.1000001m },
            Approved with { MonthlyBudgetUsd = 0 }, Approved with { MonthlyBudgetUsd = 101 },
            Approved with { MonthlyRequestLimit = 0 }, Approved with { MonthlyRequestLimit = 1001 },
            Approved with { MaximumInputBytes = 100000 }, Approved with { MaximumOutputTokens = 20000 },
            Approved with { InputUsdPerMillionTokens = 0 }, Approved with { OutputUsdPerMillionTokens = 0 },
            Approved with { TimeoutSeconds = 121 }
        }) Assert.False(invalid.IsApproved(Now));
    }

    [Fact]
    public async Task Proposal_is_reserved_once_and_cached_without_any_editorial_write()
    {
        var repository = new Repository(); var generator = new Generator();
        var service = Service(repository, generator);
        var first = await service.GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default);
        var second = await service.GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default);
        Assert.Equal(Translated, first.Text); Assert.False(first.Reused); Assert.True(second.Reused);
        Assert.Equal(first.GenerationId, second.GenerationId);
        Assert.Equal(1, generator.Calls); Assert.Equal(1, repository.Completions);
        Assert.Equal(0, repository.Failures);
        Assert.Equal(["reserve", "complete", "reserve"], repository.Events);
        Assert.Equal(3, repository.Version);
        Assert.Equal(Original().RowVersion, repository.RowVersion);
    }

    [Theory]
    [InlineData("processing", "translation-generation-pending")]
    [InlineData("failed", "translation-generation-previous-failure")]
    public async Task Existing_attempts_never_repeat_provider_calls(string state, string code)
    {
        var repository = new Repository { Reservation = new(Guid.NewGuid(), false, state, null) };
        var generator = new Generator();
        var error = await Assert.ThrowsAsync<FundingTranslationGenerationException>(() =>
            Service(repository, generator).GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default));
        Assert.Equal(code, error.Code); Assert.Equal(0, generator.Calls);
    }

    [Fact]
    public async Task Disabled_oversized_and_unfunded_requests_do_not_call_provider()
    {
        var repository = new Repository(); var generator = new Generator();
        var error = await Assert.ThrowsAsync<FundingTranslationGenerationException>(() =>
            Service(repository, generator, Approved with { Enabled = false }).GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default));
        Assert.Equal("translation-generation-disabled", error.Code); Assert.Empty(repository.Events);
        var oversized = Original() with { Data = Original().Data with { Description = new string('x', 25000) } };
        error = await Assert.ThrowsAsync<FundingTranslationGenerationException>(() =>
            Service(repository, generator).GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", oversized, default));
        Assert.Equal("translation-generation-input-too-large", error.Code); Assert.Empty(repository.Events);
        repository.BudgetFailure = true;
        await Assert.ThrowsAsync<FundingTranslationDataException>(() =>
            Service(repository, generator).GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default));
        Assert.Equal(0, generator.Calls);
    }

    [Theory]
    [InlineData(false)] [InlineData(true)]
    public async Task Incomplete_output_or_cancelled_call_retains_attempt_without_completion(bool cancel)
    {
        var repository = new Repository(); var generator = new Generator { Incomplete = !cancel, Cancel = cancel };
        var error = await Assert.ThrowsAsync<FundingTranslationGenerationException>(() =>
            Service(repository, generator).GenerateAsync(Guid.NewGuid(), Guid.NewGuid(), "es", Original(), default));
        Assert.Equal(cancel ? "translation-generation-timeout" : "translation-generation-invalid-response", error.Code);
        Assert.Equal(1, generator.Calls); Assert.Equal(0, repository.Completions); Assert.Equal(1, repository.Failures);
    }

    [Fact]
    public async Task Provider_uses_strict_schema_store_false_no_tools_and_exact_text_fields()
    {
        var handler = new Handler(_ => Success());
        var output = await Provider(handler).GenerateAsync("es", Source, default);
        Assert.Equal(Translated, output.Text); Assert.Equal(1, handler.Calls);
        using var request = JsonDocument.Parse(handler.Body!);
        var root = request.RootElement;
        Assert.False(root.GetProperty("store").GetBoolean());
        Assert.Equal("default", root.GetProperty("service_tier").GetString());
        Assert.False(root.TryGetProperty("tools", out _));
        Assert.Equal(Approved.Model, root.GetProperty("model").GetString());
        var format = root.GetProperty("text").GetProperty("format");
        Assert.True(format.GetProperty("strict").GetBoolean());
        Assert.False(format.GetProperty("schema").GetProperty("additionalProperties").GetBoolean());
        Assert.Equal(11, format.GetProperty("schema").GetProperty("required").GetArrayLength());
        Assert.Equal("https://api.openai.com/v1/responses", handler.Uri);
        var source = JsonDocument.Parse(root.GetProperty("input")[1].GetProperty("content").GetString()!);
        Assert.Equal("es", source.RootElement.GetProperty("targetLanguage").GetString());
        Assert.Equal(11, source.RootElement.GetProperty("text").EnumerateObject().Count());
    }

    [Theory]
    [InlineData("incomplete")] [InlineData("refusal")] [InlineData("extra-field")] [InlineData("missing-field")]
    [InlineData("duplicate-field")] [InlineData("wrong-model")] [InlineData("invented-field")]
    [InlineData("bad-usage")] [InlineData("null-description")] [InlineData("oversized")] [InlineData("not-json")]
    [InlineData("http-error")] [InlineData("redirect")]
    public async Task Provider_rejects_unsafe_or_partial_results_without_retry_or_body_leak(string fault)
    {
        var handler = new Handler(_ => Success(fault));
        var error = await Assert.ThrowsAsync<FundingTranslationGenerationException>(() => Provider(handler).GenerateAsync("es", Source, default));
        Assert.StartsWith("translation-generation-", error.Code);
        Assert.DoesNotContain("provider-private-payload", error.ToString());
        Assert.Equal(1, handler.Calls);
    }

    [Theory]
    [InlineData("http://api.openai.com")] [InlineData("https://example.invalid")] [InlineData("https://api.openai.com/extra")]
    [InlineData("https://api.openai.com?secret=value")]
    public async Task Provider_rejects_unapproved_destinations_before_network(string origin)
    {
        var handler = new Handler(_ => Success());
        var provider = Provider(handler, origin);
        Assert.False(provider.Configured);
        await Assert.ThrowsAsync<FundingTranslationGenerationException>(() => provider.GenerateAsync("es", Source, default));
        Assert.Equal(0, handler.Calls);
    }

    [Fact]
    public void Sql_generation_is_idempotent_budgeted_admin_only_and_separate_from_public_translations()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(x => x.Sequence == 60);
        foreach (var batch in migration.Batches.Concat(SqlScriptCatalog.DiscoverTests(root).Single(x => x.Sequence == 60).Batches))
        {
            new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(new StringReader(batch), out var errors);
            Assert.Empty(errors);
        }
        var sql = string.Join('\n', migration.Batches);
        Assert.Contains("UNIQUE(FundingOpportunityId,Language,SourceContentVersion)", sql);
        Assert.Contains("sys.sp_getapplock", sql);
        Assert.Contains("SUM(ReservedCostUsd)", sql);
        Assert.Contains("@Count >= @MonthlyRequestLimit", sql);
        Assert.Contains("FundingPlatform_usp_AdminActor_Lock", sql);
        Assert.Contains("RowVersion=@RowVersion", sql);
        Assert.DoesNotContain("UPDATE dbo.FundingPlatform_FundingTranslations", sql);
        Assert.DoesNotContain("FundingTranslation_Save", sql);
        Assert.DoesNotContain("TO FundingPlatform_WorkerRuntimeRole", sql);
        Assert.Equal(2, sql.Split("GRANT EXECUTE ON OBJECT::").Length - 1);
    }

    private static FundingTranslationGenerationService Service(Repository repo, Generator generator, FundingTranslationGenerationOptions? options = null) =>
        new(repo, generator, new() { Enabled = true }, options ?? Approved, new Clock());
    private static OpenAiFundingTranslationGenerator Provider(Handler handler, string origin = "https://api.openai.com") =>
        new(new HttpClient(handler), new() { ApiKey = "test-placeholder-not-a-real-key", EndpointOrigin = origin }, Approved, new Clock());
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }

    private static FundingOpportunityAdminDetails Original()
    {
        var data = new FundingOpportunityEditorialData("Original","Summary","Description","Sponsor",null,null,[],1,null,"https://example.invalid",null,null,
            null,null,null,FundingAmountStatus.Unknown,null,null,null,null,FundingDeadlineType.Unknown,FundingDeadlinePrecision.Unknown,
            null,null,null,null,null,null,null,null,null,null,null,null,null,FundingGeographicScope.Unknown,FundingRemoteApplication.Unknown,null,[],[],[],[],[]);
        return new(Guid.NewGuid(),"original",data,FundingPublicationStatus.Draft,true,3,100,Now,Now,
            Convert.FromHexString("0102030405060708"),[],[],[],null,null,null,null,null);
    }
    private sealed class Repository : IFundingTranslationGenerationRepository
    {
        public List<string> Events { get; } = [];
        public FundingTranslationGenerationReservation Reservation { get; set; } = new(Guid.NewGuid(), true, "processing", null);
        public int Completions { get; private set; }
        public int Failures { get; private set; }
        public int Version { get; private set; }
        public byte[]? RowVersion { get; private set; }
        public bool BudgetFailure { get; set; }
        public Task<FundingTranslationGenerationReservation> ReserveAsync(Guid actor, Guid opportunity, string language, int version, byte[] rowVersion, FundingTranslationGenerationOptions options, CancellationToken token)
        {
            Events.Add("reserve"); Version = version; RowVersion = rowVersion;
            if (BudgetFailure) throw new FundingTranslationDataException(56095, new Exception());
            return Task.FromResult(Reservation);
        }
        public Task CompleteAsync(Guid actor, Guid id, FundingTranslationGeneratedText result, CancellationToken token)
        { Events.Add("complete"); Completions++; Reservation = new(id, false, "completed", result.Text); return Task.CompletedTask; }
        public Task FailAsync(Guid actor, Guid id, CancellationToken token)
        { Events.Add("fail"); Failures++; return Task.CompletedTask; }
    }
    private sealed class Generator : IFundingTranslationGenerator
    {
        public bool Configured => true;
        public bool Cancel { get; init; }
        public bool Incomplete { get; init; }
        public int Calls { get; private set; }
        public Task<FundingTranslationGeneratedText> GenerateAsync(string language, FundingTranslationText original, CancellationToken token)
        { Calls++; if (Cancel) throw new OperationCanceledException(); return Task.FromResult(new FundingTranslationGeneratedText(Incomplete ? new("Título") : Translated, 100, 100)); }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public int Calls { get; private set; }
        public string? Body { get; private set; }
        public string? Uri { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Body = await request.Content!.ReadAsStringAsync(token); Uri = request.RequestUri?.AbsoluteUri;
            var response = respond(request); response.RequestMessage = request; return response;
        }
    }
    private static HttpResponseMessage Success(string? fault = null)
    {
        if (fault == "http-error") return new(HttpStatusCode.TooManyRequests) { Content = new StringContent("provider-private-payload") };
        if (fault == "redirect") return new(HttpStatusCode.TemporaryRedirect) { Headers = { Location = new("https://example.invalid") } };
        if (fault is "oversized" or "not-json") return new(HttpStatusCode.OK) { Content = new StringContent(fault == "oversized" ? new string('x', 262145) : "provider-private-payload") };
        var text = JsonSerializer.Serialize(Translated, FundingTranslationGenerationService.Json);
        if (fault == "extra-field") text = text[..^1] + ",\"injected\":\"provider-private-payload\"}";
        if (fault == "duplicate-field") text = text[..^1] + ",\"title\":\"provider-private-payload\"}";
        if (fault == "missing-field") text = "{}";
        if (fault == "invented-field") text = JsonSerializer.Serialize(Translated with { Requirements = "invented" }, FundingTranslationGenerationService.Json);
        if (fault == "null-description") text = JsonSerializer.Serialize(Translated with { Description = null }, FundingTranslationGenerationService.Json);
        return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
        {
            status = fault == "incomplete" ? "incomplete" : "completed", model = fault == "wrong-model" ? "other" : Approved.Model,
            output = new[] { new { type = "message", role = "assistant", content = new[] { new { type = fault == "refusal" ? "refusal" : "output_text", text } } } },
            usage = new { input_tokens = 100, output_tokens = fault == "bad-usage" ? 99999 : 100 }
        }) };
    }
}
