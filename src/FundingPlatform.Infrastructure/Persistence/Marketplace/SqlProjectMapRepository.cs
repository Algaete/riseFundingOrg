using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Core.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Sql;

namespace FundingPlatform.Infrastructure.Persistence.Marketplace;

public sealed class SqlProjectMapRepository(ISqlConnectionFactory connections) : IProjectMapRepository
{
    public async Task<ProjectMapPage> SearchAsync(ProjectMapFilters filters, CancellationToken cancellationToken)
    {
        await using var connection = connections.CreateConnection();
        using var result = await connection.QueryMultipleAsync(new CommandDefinition(
            "dbo.FundingPlatform_usp_ProjectMap_Search", CreateParameters(filters),
            commandType: CommandType.StoredProcedure, commandTimeout: 20, cancellationToken: cancellationToken));
        var counts = await result.ReadSingleAsync<MapCounts>();
        var items = (await result.ReadAsync<ProjectMapPoint>()).AsList();
        return new(items, counts.TotalCount, counts.WithoutPublicLocationCount, filters.Page, filters.PageSize);
    }

    private sealed record MapCounts(long TotalCount, long WithoutPublicLocationCount);

    internal static object CreateParameters(ProjectMapFilters filters) => new
    {
        filters.Query, filters.CountryId, filters.CategoryId, filters.ProjectStage,
        filters.SustainableDevelopmentGoalId, filters.ProjectStatus, filters.Page, filters.PageSize,
        filters.OrganizationTypeId, filters.MinimumFundingGap, filters.MaximumFundingGap, filters.Currency,
        filters.SeekingFunding, filters.SeekingPartners, filters.SeekingProfessionals, filters.SeekingConsortium,
        ProjectIdsJson = filters.ProjectIds is null ? null : JsonSerializer.Serialize(filters.ProjectIds)
    };
}
