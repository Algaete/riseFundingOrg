using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;
public sealed class SqlFundingDiscoveryRepository(ISqlConnectionFactory connections) : IFundingDiscoveryRepository
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private async Task<T?> Read<T>(string procedure, object args, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var value = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(procedure, args, commandType: CommandType.StoredProcedure, commandTimeout: 30, cancellationToken: token));
            return value is null ? default : JsonSerializer.Deserialize<T>(value, Json);
        }
        catch (SqlException error) { throw new FundingDiscoveryDataException(error.Number, error); }
    }
    public async Task<FundingDiscoveryPage> SearchAsync(FundingDiscoveryFilters filters, CancellationToken token)
        => await Read<FundingDiscoveryPage>("dbo.FundingPlatform_usp_FundingDiscovery_Search", new { FiltersJson = JsonSerializer.Serialize(filters, Json) }, token) ?? new([], 0, filters.Page, filters.PageSize);
    public Task<FundingDiscoveryAdmin?> GetAsync(Guid actor, Guid opportunityId, CancellationToken token)
        => Read<FundingDiscoveryAdmin>("dbo.FundingPlatform_usp_FundingDiscovery_AdminGet", new { UserPublicId = actor, OpportunityPublicId = opportunityId }, token);
    public async Task<CollaborationWriteResult> ReviewAsync(Guid actor, Guid opportunityId, FundingDiscoveryReview data, byte[]? version, byte[] keyHash, byte[] requestHash, CancellationToken token)
        => await Read<CollaborationWriteResult>("dbo.FundingPlatform_usp_FundingDiscovery_Review", new { UserPublicId = actor, OpportunityPublicId = opportunityId,
            data.ContentVersion, DataJson = JsonSerializer.Serialize(data.Data, Json), ExpectedVersion = version, KeyHash = keyHash, RequestHash = requestHash }, token)
            ?? throw new InvalidOperationException("Missing review result.");
}
