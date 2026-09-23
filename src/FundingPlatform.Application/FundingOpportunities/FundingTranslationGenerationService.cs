using System.Text;
using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

// Separate purpose/approval from semantic matching. Defaults authorize no spend.
public sealed record FundingTranslationGenerationOptions
{
    public bool Enabled { get; init; }
    public bool ExternalProcessingApproved { get; init; }
    public DateTimeOffset? ApprovalExpiresAtUtc { get; init; }
    public string Model { get; init; } = "";
    public int MaximumInputBytes { get; init; } = 24_000;
    public int MaximumOutputTokens { get; init; } = 8_192;
    public int TimeoutSeconds { get; init; } = 60;
    public decimal InputUsdPerMillionTokens { get; init; }
    public decimal OutputUsdPerMillionTokens { get; init; }
    public decimal MaximumCostUsdPerRequest { get; init; }
    public decimal MonthlyBudgetUsd { get; init; }
    public int MonthlyRequestLimit { get; init; }

    public bool IsApproved(DateTimeOffset now) => Enabled && ExternalProcessingApproved &&
        ApprovalExpiresAtUtc > now && Model is { Length: >= 3 and <= 100 } &&
        Model.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.') &&
        MaximumInputBytes is >= 1_000 and <= 64_000 && MaximumOutputTokens is >= 512 and <= 16_384 &&
        TimeoutSeconds is >= 10 and <= 120 &&
        InputUsdPerMillionTokens is > 0 and <= 1_000 && OutputUsdPerMillionTokens is > 0 and <= 1_000 &&
        MaximumCostUsdPerRequest is >= 0.000001m and <= 1m &&
        decimal.Round(MaximumCostUsdPerRequest, 6) == MaximumCostUsdPerRequest &&
        decimal.Round(MonthlyBudgetUsd, 6) == MonthlyBudgetUsd &&
        // Conservatively bound input by UTF-8 bytes, plus schema/prompt overhead.
        ((MaximumInputBytes + 16_384m) * InputUsdPerMillionTokens +
            MaximumOutputTokens * OutputUsdPerMillionTokens) / 1_000_000m <= MaximumCostUsdPerRequest &&
        MonthlyBudgetUsd >= MaximumCostUsdPerRequest && MonthlyBudgetUsd <= 100m &&
        MonthlyRequestLimit is >= 1 and <= 1_000;
}

public sealed record FundingTranslationGenerationRequest(int SourceContentVersion);
public sealed record FundingTranslationProposal(Guid GenerationId, string Language, int SourceContentVersion,
    FundingTranslationText Text, bool Reused);
public sealed record FundingTranslationGenerationReservation(Guid GenerationId, bool Acquired, string Status,
    FundingTranslationText? Text);
public sealed record FundingTranslationGeneratedText(FundingTranslationText Text, int InputTokens, int OutputTokens);

public interface IFundingTranslationGenerator
{
    bool Configured { get; }
    Task<FundingTranslationGeneratedText> GenerateAsync(string language, FundingTranslationText original, CancellationToken token);
}

public interface IFundingTranslationGenerationRepository
{
    Task<FundingTranslationGenerationReservation> ReserveAsync(Guid actor, Guid opportunity, string language,
        int sourceContentVersion, byte[] sourceRowVersion, FundingTranslationGenerationOptions options, CancellationToken token);
    Task CompleteAsync(Guid actor, Guid generationId, FundingTranslationGeneratedText result, CancellationToken token);
    Task FailAsync(Guid actor, Guid generationId, CancellationToken token);
}

// Only safe, fixed codes; never propagate provider payloads, prompts or credentials.
public sealed class FundingTranslationGenerationException(string code) : Exception(code)
{ public string Code { get; } = code; }

public sealed class FundingTranslationGenerationService(
    IFundingTranslationGenerationRepository repository,
    IFundingTranslationGenerator generator,
    FundingTranslationOptions translations,
    FundingTranslationGenerationOptions options,
    TimeProvider time)
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public bool Available => translations.Enabled && options.IsApproved(time.GetUtcNow()) && generator.Configured;

    public async Task<FundingTranslationProposal> GenerateAsync(Guid actor, Guid opportunity, string language,
        FundingOpportunityAdminDetails original, CancellationToken token)
    {
        if (!Available) throw new FundingTranslationGenerationException("translation-generation-disabled");
        if (!FundingTranslationRules.Supports(language)) throw new FundingTranslationGenerationException("translation-generation-invalid");
        var source = FundingTranslationRules.Normalize(FundingTranslationRules.From(original.Data));
        if (FundingTranslationRules.Validate(new(original.ContentVersion, 0, true, source), source).Count > 0 ||
            Encoding.UTF8.GetByteCount(JsonSerializer.Serialize(source, Json)) > options.MaximumInputBytes)
            throw new FundingTranslationGenerationException("translation-generation-input-too-large");

        // Persistent atomic reservation BEFORE any paid call. One attempt per version/language;
        // uncertain failures retain the reservation and are never retried automatically.
        var reservation = await repository.ReserveAsync(actor, opportunity, language, original.ContentVersion,
            original.RowVersion, options, token);
        if (!reservation.Acquired)
        {
            if (reservation.Status == "completed" && reservation.Text is { } cached &&
                FundingTranslationRules.Validate(new(original.ContentVersion, 0, true, cached), source).Count == 0)
                return new(reservation.GenerationId, language, original.ContentVersion, cached, true);
            throw new FundingTranslationGenerationException(reservation.Status == "processing"
                ? "translation-generation-pending" : "translation-generation-previous-failure");
        }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(options.TimeoutSeconds));
        try
        {
            // The approval might have expired while waiting for the SQL reservation.
            if (!Available) throw new FundingTranslationGenerationException("translation-generation-disabled");
            var result = await generator.GenerateAsync(language, source, deadline.Token);
            var text = FundingTranslationRules.Normalize(result.Text);
            if (FundingTranslationRules.Validate(new(original.ContentVersion, 0, true, text), source).Count > 0 ||
                result.InputTokens is < 1 || result.InputTokens > options.MaximumInputBytes + 16_384 ||
                result.OutputTokens is < 1 || result.OutputTokens > options.MaximumOutputTokens)
                throw new FundingTranslationGenerationException("translation-generation-invalid-response");
            await repository.CompleteAsync(actor, reservation.GenerationId, result with { Text = text }, deadline.Token);
            // A proposal is NOT a reviewed translation. Only the existing explicit Save/Approve path publishes.
            return new(reservation.GenerationId, language, original.ContentVersion, text, false);
        }
        catch (Exception error) when (error is FundingTranslationGenerationException or OperationCanceledException or FundingTranslationDataException)
        {
            using var cleanup = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            try { await repository.FailAsync(actor, reservation.GenerationId, cleanup.Token); }
            catch (Exception cleanupError) when (cleanupError is FundingTranslationDataException or OperationCanceledException) { }
            if (error is OperationCanceledException && !token.IsCancellationRequested)
                throw new FundingTranslationGenerationException("translation-generation-timeout");
            throw;
        }
    }
}
