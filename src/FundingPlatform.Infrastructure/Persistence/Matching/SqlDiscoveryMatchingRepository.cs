using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Matching;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Matching;
public sealed class SqlDiscoveryMatchingRepository(ISqlConnectionFactory factory) : IDiscoveryMatchingRepository
{
    public async Task<DiscoveryMatchingContext?> ReadAsync(Guid userId, DiscoveryMatchingRequest request, CancellationToken token)
    {
        await using var connection = factory.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
                "dbo.FundingPlatform_usp_DiscoveryMatching_Context", new { UserPublicId = userId, SourceKind = (byte)request.SourceKind,
                    SourcePublicId = request.SourceId, TargetKind = (byte)request.TargetKind },
                commandType: CommandType.StoredProcedure, commandTimeout: 30, cancellationToken: token));
            return json is null ? null : JsonSerializer.Deserialize<DiscoveryMatchingContext>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (SqlException error) { throw new DiscoveryMatchingDataException(error.Number, error); }
    }
}
