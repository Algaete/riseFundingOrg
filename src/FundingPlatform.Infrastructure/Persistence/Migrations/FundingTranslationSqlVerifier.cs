using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Core.FundingOpportunities;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

/// <summary>Checks both public result sets and localized summaries inside the caller's rollback transaction.</summary>
public static class FundingTranslationSqlVerifier
{
    public static async Task<int> VerifyAsync(SqlConnection connection, SqlTransaction transaction,
        string solutionRoot, CancellationToken cancellationToken)
    {
        if (transaction.Connection != connection)
            throw new MigrationException("translation_verification_transaction_required");
        var tag = $"translation-contract-{Guid.NewGuid():N}";
        var fixtureSql = await File.ReadAllTextAsync(Path.Combine(solutionRoot, "database", "Fixtures", "funding_translation_contract.sql"), cancellationToken);
        var fixtures = (await connection.QueryAsync<Fixture>(new CommandDefinition(fixtureSql, new { Tag = tag },
            transaction, commandTimeout: 60, cancellationToken: cancellationToken))).ToDictionary(x => x.Scenario);
        if (fixtures.Count != 5) throw new MigrationException("translation_fixture_count_invalid");
        var query = "traducida-" + tag;
        var checks = 0;

        async Task Check(string name, string search, bool enabled, int page, int size, params string[] expected)
        {
            using var result = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingOpportunity_Public_List",
                new { Query = search, PageNumber = page, PageSize = size, IncludeReviewedTranslations = enabled },
                transaction, commandTimeout: 60, commandType: CommandType.StoredProcedure, cancellationToken: cancellationToken));
            var count = await result.ReadSingleAsync<long>();
            var items = (await result.ReadAsync<SummaryRow>()).ToArray();
            var expectedPage = expected.Select(x => fixtures[x]).OrderByDescending(x => x.Id)
                .Skip((page - 1) * size).Take(size).ToArray();
            if (count != expected.Length || !items.Select(x => x.FundingOpportunityPublicId).SequenceEqual(expectedPage.Select(x => x.PublicId)) || !result.IsConsumed)
                throw new MigrationException("translation_public_result_contract_failed", name);
            foreach (var item in items)
            {
                var source = expectedPage.Single(x => x.PublicId == item.FundingOpportunityPublicId);
                if (item.Title != source.Title || item.Summary != source.Summary || item.Currency != "USD" ||
                    item.MinAmount != 100 || item.MaxAmount != 1000 || item.CoverKey != "education-v1" || item.ContentVersion != 1)
                    throw new MigrationException("translation_canonical_fields_changed", name);
            }
            checks++;
        }

        await Check("default_original_only", query, false, 1, 10);
        await Check("reviewed_current_unique", query, true, 1, 10, "title", "summary");
        await Check("first_page", query, true, 1, 1, "title", "summary");
        await Check("second_page", query, true, 2, 1, "title", "summary");
        await Check("beyond_page", query, true, 3, 1, "title", "summary");
        await Check("literal_wildcards", query + "%_['~", true, 1, 10);
        await Check("spanish_accents", "educacion traducida-" + tag, true, 1, 10, "title");
        await Check("english_title", "education traducida-" + tag, true, 1, 10, "title");
        await Check("translated_summary", "resumen traducida-" + tag, true, 1, 10, "summary");

        var references = fixtures.Values.Select(x => new FundingTranslationReference(x.PublicId, 1)).ToArray();
        using (var result = await connection.QueryMultipleAsync(new CommandDefinition(
            "dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries",
            new { ReferencesJson = JsonSerializer.Serialize(references, new JsonSerializerOptions(JsonSerializerDefaults.Web)), Language = "es" },
            transaction, commandTimeout: 60, commandType: CommandType.StoredProcedure, cancellationToken: cancellationToken)))
        {
            var summaries = (await result.ReadAsync<FundingSummaryTranslation>()).ToArray();
            var expectedIds = new[] { fixtures["title"].PublicId, fixtures["summary"].PublicId }.Order();
            if (!summaries.Select(x => x.OpportunityId).Order().SequenceEqual(expectedIds) ||
                summaries.Any(x => !x.Reviewed || x.SourceContentVersion != 1 || x.Language != "es" || x.Revision != 1 || string.IsNullOrWhiteSpace(x.Title)) ||
                !result.IsConsumed)
                throw new MigrationException("translation_summary_result_contract_failed");
            checks++;
        }

        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_FundingTranslations SET Reviewed = 0 WHERE FundingOpportunityId = @Id;",
            fixtures["title"], transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("review_withdrawn", query, true, 1, 10, "summary");
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_FundingOpportunities SET ContentVersion = 2 WHERE Id = @Id AND PublicId = @PublicId;",
            fixtures["summary"], transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("version_changed", query, true, 1, 10);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_FundingTranslations SET Reviewed = 1 WHERE FundingOpportunityId = @Id;",
            fixtures["title"], transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_Funders SET PublicationStatus = 0 WHERE Id = @FunderId;",
            fixtures["title"], transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("funder_unpublished", query, true, 1, 10);
        return checks;
    }

    private sealed record Fixture(string Scenario, long Id, Guid PublicId, string Title, string Summary, long FunderId);
    private sealed class SummaryRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public int ContentVersion { get; init; }
        public string? Title { get; init; }
        public string? Summary { get; init; }
        public string? Currency { get; init; }
        public decimal? MinAmount { get; init; }
        public decimal? MaxAmount { get; init; }
        public string? CoverKey { get; init; }
    }
}
