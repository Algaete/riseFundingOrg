using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFunderWorkspaceSourceRepository(ISqlConnectionFactory connectionFactory) : IFunderWorkspaceSourceRepository
{
    public async Task<IReadOnlyList<WorkspaceFundingSource>> ListAsync(Guid userPublicId, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        return (await connection.QueryAsync<WorkspaceFundingSource>(new CommandDefinition(
            "dbo.FundingPlatform_usp_FunderWorkspace_Sources", new { UserPublicId = userPublicId },
            commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: cancellationToken))).AsList();
    }
}
