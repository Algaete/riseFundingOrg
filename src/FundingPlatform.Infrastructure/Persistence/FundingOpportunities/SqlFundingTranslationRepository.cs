using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingTranslationRepository(ISqlConnectionFactory connections) : IFundingTranslationRepository
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private async Task<FundingTranslation?> Read(string procedure, object args, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(procedure, args,
                commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
            return json is null ? null : JsonSerializer.Deserialize<FundingTranslation>(json, Json);
        }
        catch (SqlException error) { throw new FundingTranslationDataException(error.Number, error); }
    }
    public Task<FundingTranslation?> GetAdminAsync(Guid actor, Guid id, string language, CancellationToken token) =>
        Read("dbo.FundingPlatform_usp_FundingTranslation_AdminGet", new { UserPublicId = actor, OpportunityPublicId = id, Language = language }, token);
    public Task<FundingTranslation?> GetPublishedAsync(Guid id, string language, int sourceContentVersion, CancellationToken token) =>
        Read("dbo.FundingPlatform_usp_FundingTranslation_Read", new { OpportunityPublicId = id, Language = language, SourceContentVersion = sourceContentVersion }, token);
    public async Task<IReadOnlyList<FundingSummaryTranslation>> GetPublishedSummariesAsync(
        IReadOnlyList<FundingTranslationReference> references, string language, CancellationToken token)
    {
        if (references.Count == 0) return [];
        if (references.Count > 100) throw new ArgumentOutOfRangeException(nameof(references));
        await using var connection = connections.CreateConnection();
        try
        {
            var result = await connection.QueryAsync<FundingSummaryTranslation>(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingTranslation_ReadSummaries",
                new { ReferencesJson = JsonSerializer.Serialize(references, Json), Language = language },
                commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
            return result.AsList();
        }
        catch (SqlException error) { throw new FundingTranslationDataException(error.Number, error); }
    }
    public async Task<FundingTranslation> SaveAsync(Guid actor, Guid id, string language, FundingTranslationWrite data, byte[] sourceRowVersion, CancellationToken token) =>
        await Read("dbo.FundingPlatform_usp_FundingTranslation_Save", new { UserPublicId = actor, OpportunityPublicId = id,
            Language = language, data.SourceContentVersion, data.ExpectedRevision, data.Reviewed,
            TextJson = JsonSerializer.Serialize(data.Text, Json), SourceRowVersion = sourceRowVersion }, token)
        ?? throw new InvalidOperationException("Missing translation write result.");
}
