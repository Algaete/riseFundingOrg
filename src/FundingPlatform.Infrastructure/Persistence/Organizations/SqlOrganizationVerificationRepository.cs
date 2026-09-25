using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Core.Organizations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Organizations;

public sealed class SqlOrganizationVerificationRepository(ISqlConnectionFactory connections)
    : IOrganizationVerificationRepository
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public Task<OrganizationVerification?> GetAsync(Guid adminUserPublicId,
        Guid organizationPublicId, CancellationToken cancellationToken) =>
        ReadAsync("Get", new { AdminUserPublicId = adminUserPublicId,
            OrganizationPublicId = organizationPublicId }, cancellationToken);

    public async Task<OrganizationVerification> DecideAsync(Guid adminUserPublicId,
        Guid organizationPublicId, OrganizationVerificationDecision decision,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("AdminUserPublicId", adminUserPublicId, DbType.Guid);
        parameters.Add("OrganizationPublicId", organizationPublicId, DbType.Guid);
        parameters.Add("Status", decision.Status, DbType.Int32);
        // Never truncate before SQL can enforce the full reason-length bound.
        parameters.Add("Reason", decision.Reason, DbType.String, size: -1);
        parameters.Add("ExpectedRevision", decision.ExpectedRevision, DbType.Int32);
        parameters.Add("ExpectedProfileVersion", decision.ExpectedProfileVersion, DbType.Int32);
        return await ReadAsync("Decide", parameters, cancellationToken)
            ?? throw new OrganizationVerificationDataException(56301,
                new InvalidOperationException("Missing organization verification snapshot."));
    }

    private async Task<OrganizationVerification?> ReadAsync(string operation, object parameters,
        CancellationToken cancellationToken)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var json = await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationVerification_" + operation, parameters,
                commandType: CommandType.StoredProcedure, commandTimeout: 15,
                cancellationToken: cancellationToken));
            return json is null ? null : JsonSerializer.Deserialize<OrganizationVerification>(json, Json);
        }
        catch (SqlException exception)
        {
            throw new OrganizationVerificationDataException(exception.Number, exception);
        }
    }
}
