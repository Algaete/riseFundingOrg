using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Collaboration;

public abstract class SqlCollaborationRepository(ISqlConnectionFactory connectionFactory)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    protected static string Json(object value) => JsonSerializer.Serialize(value, JsonOptions);
    protected async Task<T?> ReadAsync<T>(string procedure, object parameters, CancellationToken token) where T : class
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition("dbo.FundingPlatform_usp_" + procedure,
                parameters, commandType: CommandType.StoredProcedure, commandTimeout: 20, cancellationToken: token));
            return string.IsNullOrEmpty(json) ? null : JsonSerializer.Deserialize<T>(json, JsonOptions);
        }
        catch (SqlException exception) { throw new CollaborationDataException(exception.Number, exception); }
    }
    protected async Task<CollaborationWriteResult> WriteAsync(string procedure, object parameters, CancellationToken token)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            return await connection.QuerySingleAsync<CollaborationWriteResult>(new CommandDefinition("dbo.FundingPlatform_usp_" + procedure,
                parameters, commandType: CommandType.StoredProcedure, commandTimeout: 30, cancellationToken: token));
        }
        catch (SqlException exception) { throw new CollaborationDataException(exception.Number, exception); }
    }
}
