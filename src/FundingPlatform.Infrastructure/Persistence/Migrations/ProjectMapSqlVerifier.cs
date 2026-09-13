using System.Data;
using Dapper;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Marketplace;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

/// <summary>Consumes both real result sets inside the migrator's existing rollback transaction.</summary>
public static class ProjectMapSqlVerifier
{
    public static async Task<int> VerifyAsync(SqlConnection connection, SqlTransaction transaction,
        string solutionRoot, CancellationToken cancellationToken)
    {
        if (transaction.Connection != connection)
            throw new MigrationException("map_verification_transaction_required");
        var tag = $"map-contract-{Guid.NewGuid():N}";
        var sql = await File.ReadAllTextAsync(Path.Combine(solutionRoot, "database", "Fixtures", "project_map_contract.sql"), cancellationToken);
        var fixtures = (await connection.QueryAsync<Fixture>(new CommandDefinition(sql, new { Tag = tag },
            transaction, commandTimeout: 60, cancellationToken: cancellationToken))).ToDictionary(f => f.Scenario);
        if (fixtures.Count != 12) throw new MigrationException("map_fixture_count_invalid");
        var baseline = new ProjectMapFilters(Query: tag);
        string[] visible = ["usd", "zero", "eur", "large", "other"];
        var checks = 0;

        async Task Check(string name, ProjectMapFilters filters, string[] expected, long hidden = 0)
        {
            using var result = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_ProjectMap_Search", SqlProjectMapRepository.CreateParameters(filters),
                transaction, commandTimeout: 60, commandType: CommandType.StoredProcedure, cancellationToken: cancellationToken));
            var counts = await result.ReadSingleAsync<Counts>();
            var points = (await result.ReadAsync<ProjectMapPoint>()).ToArray();
            var expectedIds = expected.Select(key => fixtures[key]).OrderByDescending(f => f.Id)
                .Skip((filters.Page - 1) * filters.PageSize).Take(filters.PageSize).Select(f => f.PublicId);
            if (counts.TotalCount != expected.Length || counts.WithoutPublicLocationCount != hidden ||
                !points.Select(p => p.PublicId).SequenceEqual(expectedIds) ||
                points.Any(p => p.Latitude != -33.46m || p.Longitude != -70.65m) || !result.IsConsumed)
                throw new MigrationException("map_result_contract_failed", name);
            checks++;
        }

        await Check("baseline_readiness", baseline, visible, 2);
        await Check("currency", baseline with { Currency = "USD" }, ["usd", "zero", "large", "other"], 2);
        await Check("inclusive_gap", baseline with { Currency = "USD", MinimumFundingGap = 75, MaximumFundingGap = 75 }, ["usd", "other"], 2);
        await Check("zero_gap", baseline with { Currency = "USD", MinimumFundingGap = 0, MaximumFundingGap = 0 }, ["zero"]);
        await Check("decimal_precision", baseline with { Currency = "USD", MinimumFundingGap = 900.1234m, MaximumFundingGap = 900.1234m }, ["large"]);
        await Check("decimal_exclusion", baseline with { Currency = "USD", MinimumFundingGap = 900, MaximumFundingGap = 900.1233m }, []);
        await Check("organization_type", baseline with { OrganizationTypeId = 2 }, ["usd", "zero", "eur", "large"], 2);
        await Check("funding_need", baseline with { SeekingFunding = true }, ["usd", "eur", "large", "other"], 2);
        await Check("partners", baseline with { SeekingPartners = true }, ["usd", "eur"], 2);
        await Check("professionals", baseline with { SeekingProfessionals = true }, ["usd", "large"], 2);
        await Check("consortium", baseline with { SeekingConsortium = true }, ["usd", "other"], 2);
        await Check("combined", baseline with { CountryId = 152, CategoryId = 1, OrganizationTypeId = 2,
            ProjectStage = 1, ProjectStatus = 2, SustainableDevelopmentGoalId = 13, Currency = "USD",
            MinimumFundingGap = 75, MaximumFundingGap = 75, SeekingFunding = true,
            SeekingPartners = true, SeekingProfessionals = true, SeekingConsortium = true }, ["usd"], 2);
        await Check("other_geography", baseline with { CountryId = 392, CategoryId = 2 }, ["other"]);
        await Check("stage_and_status", baseline with { ProjectStage = 0, ProjectStatus = 4, SustainableDevelopmentGoalId = 4 }, ["zero"]);
        await Check("selected_ids_do_not_bypass_readiness", baseline with { ProjectIds = [
            fixtures["usd"].PublicId, fixtures["hidden"].PublicId, fixtures["draft"].PublicId,
            fixtures["inactive-project"].PublicId, fixtures["inactive-org"].PublicId,
            fixtures["unready-org"].PublicId, fixtures["unknown"].PublicId, Guid.NewGuid()] }, ["usd"], 1);
        await Check("literal_query", baseline with { Query = tag + "%_['" }, []);
        for (var page = 1; page <= 4; page++)
            await Check($"page_{page}_global_counts", baseline with { Page = page, PageSize = 2 }, visible, 2);

        var primary = fixtures["usd"];
        var selected = baseline with { ProjectIds = [primary.PublicId] };
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 0 WHERE Id = @Id AND PublicId = @PublicId;",
            primary, transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("publication_revoked", selected, []);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_Projects SET PublicationStatus = 2, EnrichmentJson = JSON_MODIFY(EnrichmentJson, '$.locationVisibility', 0) WHERE Id = @Id AND PublicId = @PublicId;",
            primary, transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("consent_revoked", selected, [], 1);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE dbo.FundingPlatform_Organizations SET IsActive = 0 WHERE Id = @OrganizationId;",
            primary, transaction, commandTimeout: 30, cancellationToken: cancellationToken));
        await Check("organization_revoked", selected, []);
        return checks;
    }

    private sealed record Counts(long TotalCount, long WithoutPublicLocationCount);
    private sealed record Fixture(string Scenario, long Id, Guid PublicId, long OrganizationId);
}
