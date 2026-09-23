using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Stories;
using FundingPlatform.Core.Stories;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Stories;

public sealed class SqlStoryRepository(ISqlConnectionFactory connections) : IStoryRepository
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    public async Task<StoryPage> ListAsync(Guid? actor, Guid? organization, Guid? project, Guid? story, int page, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var result = await connection.QuerySingleAsync<string>(new CommandDefinition("dbo.FundingPlatform_usp_Story_List",
                new { UserPublicId = actor, OrganizationPublicId = organization, ProjectPublicId = project, StoryPublicId = story, Page = page },
                commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
            return JsonSerializer.Deserialize<StoryPage>(result, Json)!;
        }
        catch (SqlException error) { throw new StoryDataException(error.Number, error); }
    }
    public Task SaveAsync(Guid actor, Guid organization, Guid story, StoryWrite data, CancellationToken token) =>
        Execute("dbo.FundingPlatform_usp_Story_Save", new { UserPublicId = actor, OrganizationPublicId = organization,
            StoryPublicId = story, data.ExpectedRevision, ContentJson = JsonSerializer.Serialize(data.Content, Json) }, token);
    public Task PublishAsync(Guid actor, Guid organization, Guid story, StoryPublication data, CancellationToken token) =>
        Execute("dbo.FundingPlatform_usp_Story_Publish", new { UserPublicId = actor, OrganizationPublicId = organization,
            StoryPublicId = story, data.ExpectedRevision, data.Publish, data.RightsConfirmed, data.PersonalConsentConfirmed }, token);
    private async Task Execute(string procedure, object args, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try { await connection.ExecuteAsync(new CommandDefinition(procedure, args, commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token)); }
        catch (SqlException error) { throw new StoryDataException(error.Number, error); }
    }
}
