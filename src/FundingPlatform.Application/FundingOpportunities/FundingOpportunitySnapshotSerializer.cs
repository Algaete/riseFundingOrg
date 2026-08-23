using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed record FundingOpportunitySnapshot(
    short Version,
    string Json,
    byte[] Hash);

public static class FundingOpportunitySnapshotSerializer
{
    public const short CurrentVersion = 1;
    private const int MaximumSnapshotBytes = 262_144;

    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        MaxDepth = 32,
        PropertyNameCaseInsensitive = false,
        WriteIndented = false
    };

    public static FundingOpportunitySnapshot Serialize(
        ExternalFundingOpportunity opportunity)
    {
        ArgumentNullException.ThrowIfNull(opportunity);
        var json = JsonSerializer.Serialize(
            new SnapshotEnvelope(CurrentVersion, opportunity), Options);
        var bytes = Encoding.UTF8.GetBytes(json);
        if (bytes.Length > MaximumSnapshotBytes)
        {
            throw new InvalidOperationException(
                "The normalized funding opportunity snapshot is too large.");
        }

        return new FundingOpportunitySnapshot(
            CurrentVersion,
            json,
            SHA256.HashData(bytes));
    }

    public static byte[] ComputeSemanticHash(
        ExternalFundingOpportunity opportunity)
    {
        ArgumentNullException.ThrowIfNull(opportunity);
        var json = JsonSerializer.Serialize(new SemanticSnapshotEnvelope(
            CurrentVersion,
            new SemanticSnapshot(
                opportunity.ProviderCode,
                opportunity.ExternalId,
                opportunity.ReferenceNumber,
                opportunity.Title,
                opportunity.SponsorName,
                opportunity.Description,
                opportunity.EligibilityDescription,
                opportunity.FundingInstrument,
                opportunity.FundingCategoriesDescription,
                opportunity.OpenDate,
                opportunity.CloseDate,
                opportunity.MinimumAmount,
                opportunity.MaximumAmount,
                opportunity.RequiresCofunding,
                opportunity.SourceUrl,
                opportunity.ApplicationUrl)), Options);
        return SHA256.HashData(Encoding.UTF8.GetBytes(json));
    }

    public static bool TryDeserialize(
        short version,
        string? json,
        byte[]? expectedHash,
        out ExternalFundingOpportunity opportunity)
    {
        opportunity = default!;
        if (version != CurrentVersion ||
            string.IsNullOrWhiteSpace(json) ||
            expectedHash is not { Length: 32 })
        {
            return false;
        }

        var bytes = Encoding.UTF8.GetBytes(json);
        if (bytes.Length > MaximumSnapshotBytes ||
            !CryptographicOperations.FixedTimeEquals(
                SHA256.HashData(bytes), expectedHash))
        {
            return false;
        }

        try
        {
            var envelope = JsonSerializer.Deserialize<SnapshotEnvelope>(json, Options);
            if (envelope is null ||
                envelope.SchemaVersion != version ||
                !IsValid(envelope.Opportunity))
            {
                return false;
            }

            opportunity = envelope.Opportunity;
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static bool IsValid(ExternalFundingOpportunity? opportunity) =>
        opportunity is not null &&
        !string.IsNullOrWhiteSpace(opportunity.ProviderCode) &&
        opportunity.ProviderCode.Length <= 100 &&
        !string.IsNullOrWhiteSpace(opportunity.ExternalId) &&
        opportunity.ExternalId.Length <= 250 &&
        !string.IsNullOrWhiteSpace(opportunity.ReferenceNumber) &&
        opportunity.ReferenceNumber.Length <= 250 &&
        !string.IsNullOrWhiteSpace(opportunity.Title) &&
        opportunity.Title.Length <= 500 &&
        !string.IsNullOrWhiteSpace(opportunity.SponsorName) &&
        opportunity.SponsorName.Length <= 300 &&
        Uri.TryCreate(opportunity.SourceUrl, UriKind.Absolute, out var sourceUri) &&
        sourceUri.Scheme == Uri.UriSchemeHttps &&
        opportunity.RetrievedAtUtc.Offset == TimeSpan.Zero;

    private sealed record SnapshotEnvelope(
        short SchemaVersion,
        ExternalFundingOpportunity Opportunity);

    private sealed record SemanticSnapshot(
        string ProviderCode,
        string ExternalId,
        string ReferenceNumber,
        string Title,
        string SponsorName,
        string? Description,
        string? EligibilityDescription,
        string? FundingInstrument,
        string? FundingCategoriesDescription,
        DateOnly? OpenDate,
        DateOnly? CloseDate,
        decimal? MinimumAmount,
        decimal? MaximumAmount,
        bool? RequiresCofunding,
        string SourceUrl,
        string? ApplicationUrl);

    private sealed record SemanticSnapshotEnvelope(
        short SchemaVersion,
        SemanticSnapshot Opportunity);
}
