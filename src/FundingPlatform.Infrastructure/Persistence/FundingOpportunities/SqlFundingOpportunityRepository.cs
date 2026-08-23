using System.Data;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingOpportunityRepository(
    ISqlConnectionFactory connectionFactory) : IFundingOpportunityRepository
{
    private static readonly JsonSerializerOptions SnapshotOptions = new(JsonSerializerDefaults.Web);

    public async Task<FundingOpportunityUpsertResult> UpsertExternalWithIdentityAsync(
        int expectedFundingSourceId,
        string expectedProviderCode,
        ExternalFundingOpportunity opportunity,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(opportunity);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(expectedFundingSourceId);
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedProviderCode);
        if (expectedProviderCode.Length > 100 ||
            !string.Equals(expectedProviderCode, expectedProviderCode.Trim(), StringComparison.Ordinal))
        {
            throw new ArgumentException(
                "The expected provider code is invalid.", nameof(expectedProviderCode));
        }
        ArgumentException.ThrowIfNullOrWhiteSpace(opportunity.ProviderCode);
        ArgumentException.ThrowIfNullOrWhiteSpace(opportunity.ExternalId);
        ArgumentException.ThrowIfNullOrWhiteSpace(opportunity.SourceUrl);
        EnsureMatchingProvider(expectedProviderCode, opportunity.ProviderCode);

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            await connection.OpenAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                var row = await connection.QuerySingleAsync<StageMutationRow>(new CommandDefinition(
                    "dbo.FundingPlatform_usp_FundingOpportunity_StageExternal",
                    BuildStageParameters(
                        expectedFundingSourceId, expectedProviderCode, opportunity),
                    transaction,
                    commandType: CommandType.StoredProcedure,
                    commandTimeout: 30,
                    cancellationToken: cancellationToken));
                if (!row.Succeeded)
                {
                    throw new InvalidOperationException(
                        $"External funding observation was rejected ({NormalizeStageError(row.Code)})." );
                }

                await transaction.CommitAsync(cancellationToken);
                var outcome = row.Code switch
                {
                    "draft-created" => FundingOpportunityUpsertOutcome.Created,
                    "draft-updated" => FundingOpportunityUpsertOutcome.Updated,
                    "unchanged" => FundingOpportunityUpsertOutcome.Unchanged,
                    "pending-review-protected" or "published-protected" or
                        "archived-protected" or "manual-lock-protected" =>
                        FundingOpportunityUpsertOutcome.StagedForReview,
                    _ => throw new InvalidOperationException(
                        "SQL returned an unknown external staging outcome.")
                };
                return new FundingOpportunityUpsertResult(
                    outcome, row.FundingOpportunityPublicId);
            }
            catch
            {
                await transaction.RollbackAsync(CancellationToken.None);
                throw;
            }
        }
        catch (SqlException exception)
        {
            throw Wrap("stage external funding opportunity", exception);
        }
    }

    public async Task<FundingOpportunityPage> SearchPublishedAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Public_List",
                new { Query = query, PageNumber = pageNumber, PageSize = pageSize },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<PublicSummaryRow>()).AsList();
            return new FundingOpportunityPage(
                rows.Select(MapPublicSummary).ToArray(), totalCount, pageNumber, pageSize);
        }
        catch (SqlException exception)
        {
            throw Wrap("search published funding opportunities", exception);
        }
    }

    public async Task<FundingOpportunityDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Public_GetBySlug",
                new { Slug = slug },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<PublicDetailsRow>();
            if (row is null)
            {
                return null;
            }

            _ = await reader.ReadAsync<ShortIdRow>();
            _ = await reader.ReadAsync<IntIdRow>();
            _ = await reader.ReadAsync<IntIdRow>();
            _ = await reader.ReadAsync<IntIdRow>();
            _ = await reader.ReadAsync<IntIdRow>();
            var funders = (await reader.ReadAsync<PublicFunderRow>())
                .Select(item => new FundingOpportunityFunder(
                    item.FunderPublicId,
                    item.Slug,
                    item.Name,
                    (FunderOpportunityRole)item.Role))
                .ToArray();
            var sources = (await reader.ReadAsync<PublicSourceRow>()).AsList();
            var primarySource = sources.FirstOrDefault(source => source.IsPrimary && source.IsActive)
                ?? sources.FirstOrDefault(source => source.IsActive)
                ?? sources.FirstOrDefault();

            return new FundingOpportunityDetails(
                row.FundingOpportunityPublicId,
                row.Slug,
                row.Title,
                row.Description,
                row.Summary,
                row.SponsorName,
                row.SponsorUrl,
                row.ApplicationUrl,
                row.Currency?.Trim(),
                row.MinAmount,
                row.MaxAmount,
                ToDateOnly(row.OpenDate),
                ToDateOnly(row.CloseDate),
                row.EligibilityDescription,
                row.Requirements,
                row.Objectives,
                row.RequiresCofunding,
                row.SourceName,
                row.SourceUrl,
                primarySource?.ExternalId,
                ToUtc(row.LastVerifiedAtUtc ?? row.PublishedAtUtc),
                row.DataQualityScore,
                funders);
        }
        catch (SqlException exception)
        {
            throw Wrap("read published funding opportunity", exception);
        }
    }

    private static object BuildStageParameters(
        int sourceId,
        string expectedProviderCode,
        ExternalFundingOpportunity opportunity)
    {
        var hasAmount = opportunity.MinimumAmount.HasValue || opportunity.MaximumAmount.HasValue;
        var summary = Truncate(opportunity.Description, 2000);
        var snapshot = JsonSerializer.Serialize(opportunity, SnapshotOptions);
        return new
        {
            FundingSourceId = sourceId,
            ExpectedProviderCode = expectedProviderCode,
            ExternalId = Truncate(opportunity.ReferenceNumber, 250),
            // Source links expose ReferenceNumber as ExternalId in the editorial contract.
            // Keep both identifiers aligned so an administrator can round-trip imported rows.
            SourceItemKeyHash = Hash(opportunity.ReferenceNumber),
            opportunity.SourceUrl,
            CanonicalUrlHash = Hash(opportunity.SourceUrl),
            ObservedAtUtc = opportunity.RetrievedAtUtc.UtcDateTime,
            Slug = CreateExternalSlug(expectedProviderCode, opportunity.ExternalId),
            opportunity.Title,
            opportunity.Description,
            Summary = summary,
            opportunity.SponsorName,
            SponsorUrl = (string?)null,
            opportunity.ApplicationUrl,
            FundingTypeId = opportunity.FundingInstrument?.Contains(
                "Grant", StringComparison.OrdinalIgnoreCase) == true ? (short?)1 : null,
            Currency = hasAmount ? "USD" : null,
            MinAmount = opportunity.MinimumAmount,
            MaxAmount = opportunity.MaximumAmount,
            AmountStatus = hasAmount ? (byte)1 : (byte)0,
            OpenDate = ToDateTime(opportunity.OpenDate),
            CloseDate = ToDateTime(opportunity.CloseDate),
            DeadlineType = opportunity.CloseDate.HasValue ? (byte)1 : (byte)0,
            DeadlinePrecision = opportunity.CloseDate.HasValue ? (byte)1 : (byte)0,
            opportunity.EligibilityDescription,
            Objectives = opportunity.FundingCategoriesDescription,
            opportunity.RequiresCofunding,
            CofundingPercentage = (decimal?)null,
            DataQualityScore = CalculateQualityScore(opportunity, hasAmount),
            SnapshotJson = snapshot,
            ContentHash = FundingOpportunitySnapshotSerializer.ComputeSemanticHash(opportunity)
        };
    }

    private static FundingOpportunitySummary MapPublicSummary(PublicSummaryRow row) => new(
        row.FundingOpportunityPublicId,
        row.Slug,
        row.Title,
        row.Summary,
        row.SponsorName,
        row.Currency?.Trim(),
        row.MinAmount,
        row.MaxAmount,
        ToDateOnly(row.OpenDate),
        ToDateOnly(row.CloseDate),
        row.SourceName,
        row.SourceUrl,
        ToUtc(row.PublishedAtUtc),
        row.DataQualityScore);

    private static string CreateExternalSlug(string providerCode, string externalId)
    {
        var normalized = $"{providerCode}-{externalId}".Normalize(NormalizationForm.FormD);
        var baseValue = new string(normalized
            .Where(character => CharUnicodeInfo.GetUnicodeCategory(character) !=
                UnicodeCategory.NonSpacingMark)
            .Select(character => char.IsLetterOrDigit(character)
                ? char.ToLowerInvariant(character)
                : '-')
            .ToArray());
        baseValue = string.Join('-', baseValue.Split('-', StringSplitOptions.RemoveEmptyEntries));
        if (baseValue.Length == 0)
        {
            baseValue = "external-funding";
        }
        var suffix = Convert.ToHexString(Hash($"{providerCode}\n{externalId}").AsSpan(0, 4))
            .ToLowerInvariant();
        if (baseValue.Length > 311)
        {
            baseValue = baseValue[..311].TrimEnd('-');
        }

        return $"{baseValue}-{suffix}";
    }

    private static decimal CalculateQualityScore(
        ExternalFundingOpportunity opportunity,
        bool hasAmount)
    {
        var qualityScore = 60m;
        qualityScore += opportunity.Description is null ? 0 : 10;
        qualityScore += opportunity.EligibilityDescription is null ? 0 : 10;
        qualityScore += opportunity.CloseDate is null ? 0 : 10;
        qualityScore += hasAmount ? 10 : 0;
        return qualityScore;
    }

    private static string NormalizeStageError(string code) => code switch
    {
        "source-disabled" or "slug-conflict" or "source-link-conflict" or
            "invalid-document" => code,
        _ => "staging-rejected"
    };

    private static void EnsureMatchingProvider(
        string expectedProviderCode,
        string observedProviderCode)
    {
        if (!string.Equals(
                expectedProviderCode, observedProviderCode, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "Funding source metadata does not match the external observation.");
        }
    }

    private static byte[] Hash(string value) =>
        SHA256.HashData(Encoding.UTF8.GetBytes(value));

    private static string? Truncate(string? value, int maximumLength)
    {
        if (value is null || value.Length <= maximumLength)
        {
            return value;
        }

        return value[..maximumLength];
    }

    private static DateTime? ToDateTime(DateOnly? value) =>
        value?.ToDateTime(TimeOnly.MinValue);

    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static FundingOpportunityDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class StageMutationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = string.Empty;
        public Guid? FundingOpportunityPublicId { get; init; }
        public int? ContentVersion { get; init; }
        public byte? PublicationStatus { get; init; }
        public byte[]? RowVersion { get; init; }
        public Guid? StagedRevisionPublicId { get; init; }
    }

    private class PublicSummaryRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Title { get; init; } = string.Empty;
        public string? Summary { get; init; }
        public string SponsorName { get; init; } = string.Empty;
        public string? Currency { get; init; }
        public decimal? MinAmount { get; init; }
        public decimal? MaxAmount { get; init; }
        public DateTime? OpenDate { get; init; }
        public DateTime? CloseDate { get; init; }
        public DateTime PublishedAtUtc { get; init; }
        public decimal DataQualityScore { get; init; }
        public string SourceName { get; init; } = string.Empty;
        public string? SourceUrl { get; init; }
    }

    private sealed class PublicDetailsRow : PublicSummaryRow
    {
        public string? Description { get; init; }
        public string? SponsorUrl { get; init; }
        public string? ApplicationUrl { get; init; }
        public string? EligibilityDescription { get; init; }
        public string? Requirements { get; init; }
        public string? Objectives { get; init; }
        public bool? RequiresCofunding { get; init; }
        public DateTime? LastVerifiedAtUtc { get; init; }
    }

    private sealed class ShortIdRow
    {
        public short Id { get; init; }
    }

    private sealed class IntIdRow
    {
        public int Id { get; init; }
    }

    private sealed class PublicFunderRow
    {
        public Guid FunderPublicId { get; init; }
        public string Slug { get; init; } = string.Empty;
        public string Name { get; init; } = string.Empty;
        public byte Role { get; init; }
    }

    private sealed class PublicSourceRow
    {
        public string? ExternalId { get; init; }
        public bool IsPrimary { get; init; }
        public bool IsActive { get; init; }
    }
}
