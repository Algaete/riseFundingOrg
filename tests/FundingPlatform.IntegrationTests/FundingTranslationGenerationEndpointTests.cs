using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace FundingPlatform.IntegrationTests;

public sealed partial class FundingEditorialEndpointTests
{
    private readonly GenerationRepository generations = new();
    private readonly TranslationGenerator generator = new();
    private static string GeneratePath => TranslationPath + "/generate";
    private void ConfigureTranslationGeneration(IServiceCollection services)
    {
        services.RemoveAll<FundingTranslationGenerationOptions>();
        services.RemoveAll<IFundingTranslationGenerationRepository>();
        services.RemoveAll<IFundingTranslationGenerator>();
        services.AddSingleton<IFundingTranslationGenerationRepository>(generations);
        services.AddSingleton<IFundingTranslationGenerator>(generator);
        services.AddSingleton(new FundingTranslationGenerationOptions
        {
            Enabled = true, ExternalProcessingApproved = true, ApprovalExpiresAtUtc = DateTimeOffset.UtcNow.AddDays(1),
            Model = "test-model", InputUsdPerMillionTokens = 1, OutputUsdPerMillionTokens = 2,
            MaximumCostUsdPerRequest = 0.1m, MonthlyBudgetUsd = 1, MonthlyRequestLimit = 10
        });
    }

    [Fact]
    public async Task Automatic_generation_requires_admin_and_mfa_and_never_calls_provider_anonymously()
    {
        using var anonymous = await client.PostAsJsonAsync(GeneratePath, new { sourceContentVersion = 3 });
        Assert.Equal(HttpStatusCode.Unauthorized, anonymous.StatusCode);
        foreach (var (role, mfa) in new[] { (PlatformRoles.Admin, false), ("OrganizationOwner", true) })
        {
            using var request = AuthenticatedRequest(HttpMethod.Post, GeneratePath, role, mfa);
            request.Content = JsonContent.Create(new { sourceContentVersion = 3 });
            using var response = await client.SendAsync(request);
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
        Assert.Equal(0, generator.Calls); Assert.Equal(0, generations.Reservations);
    }

    [Theory]
    [InlineData(null, 3, 428)] [InlineData(CurrentETag, 2, 412)] [InlineData(NextETag, 3, 412)]
    public async Task Generation_enforces_loaded_source_version_before_reserving(string? eTag, int version, int expected)
    {
        opportunities.Details = TranslationOriginal();
        using var request = GenerationRequest(eTag, version);
        using var response = await client.SendAsync(request);
        Assert.Equal(expected, (int)response.StatusCode);
        Assert.Equal(0, generator.Calls); Assert.Equal(0, generations.Reservations);
    }

    [Fact]
    public async Task Generation_returns_no_store_proposal_and_preserves_editorial_translation()
    {
        opportunities.Details = TranslationOriginal();
        using var request = GenerationRequest(CurrentETag);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("no-store", response.Headers.CacheControl?.ToString());
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("Propuesta", body.RootElement.GetProperty("text").GetProperty("title").GetString());
        Assert.False(body.RootElement.TryGetProperty("reviewed", out _));
        Assert.False(body.RootElement.GetProperty("reused").GetBoolean());
        Assert.Equal(1, generator.Calls); Assert.Equal(1, generations.Completions);
        Assert.Null(translations.Saved);
    }

    [Theory]
    [InlineData(56095, 429)] [InlineData(56032, 412)] [InlineData(51601, 403)]
    public async Task Generation_handles_budget_version_and_database_authorization_without_provider(int code, int expected)
    {
        opportunities.Details = TranslationOriginal(); generations.Error = code;
        using var request = GenerationRequest(CurrentETag);
        using var response = await client.SendAsync(request);
        Assert.Equal(expected, (int)response.StatusCode); Assert.Equal(0, generator.Calls);
    }

    [Fact]
    public async Task Generation_disabled_is_reported_by_metadata_and_blocks_paid_route()
    {
        opportunities.Details = TranslationOriginal(); generator.Configured = false;
        using var get = AuthenticatedRequest(HttpMethod.Get, TranslationPath, PlatformRoles.Admin, true);
        using var metadata = await client.SendAsync(get);
        using var body = JsonDocument.Parse(await metadata.Content.ReadAsStringAsync());
        Assert.False(body.RootElement.GetProperty("generationAvailable").GetBoolean());
        using var request = GenerationRequest(CurrentETag);
        using var response = await client.SendAsync(request);
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal(0, generator.Calls); Assert.Equal(0, generations.Reservations);
    }

    private static HttpRequestMessage GenerationRequest(string? eTag, int version = 3)
    {
        var request = AuthenticatedRequest(HttpMethod.Post, GeneratePath, PlatformRoles.Admin, true);
        request.Content = JsonContent.Create(new { sourceContentVersion = version });
        if (eTag != null) request.Headers.TryAddWithoutValidation("If-Match", eTag);
        return request;
    }
    private sealed class GenerationRepository : IFundingTranslationGenerationRepository
    {
        public int? Error { get; set; }
        public int Reservations { get; private set; }
        public int Completions { get; private set; }
        public Task<FundingTranslationGenerationReservation> ReserveAsync(Guid actor, Guid opportunity, string language, int version, byte[] rowVersion, FundingTranslationGenerationOptions options, CancellationToken token)
        {
            Reservations++;
            if (Error is int code) throw new FundingTranslationDataException(code, new Exception("private database detail"));
            return Task.FromResult(new FundingTranslationGenerationReservation(Guid.NewGuid(), true, "processing", null));
        }
        public Task CompleteAsync(Guid actor, Guid id, FundingTranslationGeneratedText result, CancellationToken token) { Completions++; return Task.CompletedTask; }
        public Task FailAsync(Guid actor, Guid id, CancellationToken token) => Task.CompletedTask;
    }
    private sealed class TranslationGenerator : IFundingTranslationGenerator
    {
        public bool Configured { get; set; } = true;
        public int Calls { get; private set; }
        public Task<FundingTranslationGeneratedText> GenerateAsync(string language, FundingTranslationText original, CancellationToken token)
        { Calls++; return Task.FromResult(new FundingTranslationGeneratedText(new("Propuesta", "Resumen", "Descripción"), 100, 100)); }
    }
}
