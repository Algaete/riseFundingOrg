using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Engagement;
using FundingPlatform.Core.Engagement;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Engagement;

public sealed class SqlInquiryRepository(ISqlConnectionFactory connections) : IInquiryRepository
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private async Task<T?> Read<T>(string procedure, object args, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition("dbo.FundingPlatform_usp_Inquiry_" + procedure,
                args, commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
            return json is null ? default : JsonSerializer.Deserialize<T>(json, Json);
        }
        catch (SqlException e) { throw new InquiryDataException(e.Number, e); }
    }
    public async Task<InquiryReceipt> CaptureAsync(InquiryInput data, byte[] hash, CancellationToken token) =>
        await Read<InquiryReceipt>("Capture", new { data.RequestId, DataJson = JsonSerializer.Serialize(data, Json), RequestHash = hash }, token)
        ?? throw new InvalidOperationException("Missing inquiry receipt.");
    public async Task<InquiryPage> ListAsync(Guid actor, int page, CancellationToken token) =>
        await Read<InquiryPage>("List", new { UserPublicId = actor, Page = page }, token)
        ?? throw new InvalidOperationException("Missing inquiry page.");
    public Task ReviewAsync(Guid actor, Guid id, InquiryReview data, CancellationToken token) =>
        Execute("Review", new { UserPublicId = actor, RequestId = id, data.ExpectedRevision, data.Status }, token);
    public Task<Inquiry?> ClaimNotificationAsync(Guid id, CancellationToken token) => Read<Inquiry>("ClaimNotification", new { RequestId = id }, token);
    public Task FinishNotificationAsync(Guid id, bool accepted, CancellationToken token) =>
        Execute("FinishNotification", new { RequestId = id, Accepted = accepted }, token);
    private async Task Execute(string procedure, object args, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try { await connection.ExecuteAsync(new CommandDefinition("dbo.FundingPlatform_usp_Inquiry_" + procedure,
            args, commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token)); }
        catch (SqlException e) { throw new InquiryDataException(e.Number, e); }
    }
}
