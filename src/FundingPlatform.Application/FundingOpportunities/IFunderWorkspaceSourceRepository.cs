using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public interface IFunderWorkspaceSourceRepository
{
    Task<IReadOnlyList<WorkspaceFundingSource>> ListAsync(Guid userPublicId, CancellationToken cancellationToken);
}
