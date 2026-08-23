using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FundingSourceAdminService(IFundingSourceAdminRepository repository)
{
    public async Task<FundingEditorialQueryResult<IReadOnlyList<FundingSourceAdminOption>>> ListAsync(
        Guid adminUserPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            return new FundingEditorialQueryResult<IReadOnlyList<FundingSourceAdminOption>>(
                FundingEditorialOutcome.Success,
                await repository.ListAsync(adminUserPublicId, cancellationToken));
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialQueryResult<IReadOnlyList<FundingSourceAdminOption>>(
                FundingEditorialOutcome.Forbidden);
        }
    }
}
