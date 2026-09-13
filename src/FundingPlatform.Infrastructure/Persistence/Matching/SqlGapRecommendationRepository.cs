using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Matching;

public sealed class SqlGapRecommendationRepository(ISqlConnectionFactory factory) : IGapRecommendationRepository
{
    public async Task<GapRecommendationContext?> ReadAsync(Guid userId, GapRecommendationRequest request, CancellationToken token)
    {
        await using var connection = factory.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
                "dbo.FundingPlatform_usp_GapRecommendations_Context",
                new { UserPublicId = userId, ProjectPublicId = request.ProjectId, OpportunityPublicId = request.OpportunityId },
                commandType: CommandType.StoredProcedure, commandTimeout: 30, cancellationToken: token));
            return json is null ? null : JsonSerializer.Deserialize<GapRecommendationContext>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (SqlException error) { throw new DiscoveryMatchingDataException(error.Number, error); }
    }
}
