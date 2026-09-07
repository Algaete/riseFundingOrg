using FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

namespace FundingPlatform.UnitTests;

public sealed class ExternalFundingOpportunityStagingTests
{
    [Theory]
    [InlineData(true, null, null)]
    [InlineData(true, 25d, true)]
    [InlineData(false, null, false)]
    [InlineData(null, null, null)]
    public void Canonical_cofunding_requires_a_known_percentage_when_true(
        bool? requiresCofunding,
        double? cofundingPercentage,
        bool? expected)
    {
        var percentage = cofundingPercentage.HasValue
            ? (decimal?)Convert.ToDecimal(cofundingPercentage.Value)
            : null;

        var actual = SqlFundingOpportunityRepository.NormalizeImportedCofundingRequirement(
            requiresCofunding,
            percentage);

        Assert.Equal(expected, actual);
    }
}
