using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Validation;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class FundingEligibilityPolicyTests
{
    private static FundingEligibilityPolicy Policy => new("https://example.org/criteria",
        new(10_000, "USD", false), new(50_000, "USD", false), [1], [1], ["Volunteer led"]);

    [Fact]
    public void Missing_review_is_distinct_from_reviewed_without_additional_constraints()
    {
        Assert.Null(FundingEligibilityPolicyRules.Normalize(null));
        var reviewed = FundingEligibilityPolicyRules.Normalize(new("https://example.org/criteria"));
        Assert.NotNull(reviewed);
        Assert.Empty(reviewed.RequiredCategoryIds!);
        Assert.Empty(reviewed.ManualRequirements!);
        Assert.Null(reviewed.ProjectBudgetLimit);
    }

    [Fact]
    public void Normalization_preserves_exclusive_boundaries_and_manual_requirements()
    {
        var normalized = FundingEligibilityPolicyRules.Normalize(Policy with
        { SourceUrl = " https://example.org/criteria ", ProjectBudgetLimit = new(10000, " usd ", false),
          RequiredCategoryIds = [2, 1, 2], ManualRequirements = [" Volunteer led ", "Volunteer led"] });
        Assert.Equal([1, 2], normalized!.RequiredCategoryIds);
        Assert.Equal("USD", normalized.ProjectBudgetLimit!.Currency);
        Assert.False(normalized.ProjectBudgetLimit.Inclusive);
        Assert.Single(normalized.ManualRequirements!);
        var errors = new FieldValidationErrors();
        FundingEligibilityPolicyRules.Validate(normalized, errors);
        Assert.Empty(errors);
    }

    [Theory]
    [InlineData("http://example.org/criteria")]
    [InlineData("https://name:password@example.org/criteria")]
    [InlineData("not-a-url")]
    public void Source_must_be_https_without_embedded_credentials(string url)
    {
        var errors = new FieldValidationErrors();
        FundingEligibilityPolicyRules.Validate(Policy with { SourceUrl = url }, errors);
        Assert.Contains("eligibilityPolicy.sourceUrl", errors.Keys);
    }

    [Theory]
    [InlineData("0", "USD")]
    [InlineData("-1", "USD")]
    [InlineData("1000000000000000", "USD")]
    [InlineData("1.00001", "USD")]
    [InlineData("10000", "US")]
    public void Invalid_budget_limits_are_rejected(string amount, string currency)
    {
        var errors = new FieldValidationErrors();
        FundingEligibilityPolicyRules.Validate(Policy with { ProjectBudgetLimit =
            new(decimal.Parse(amount, System.Globalization.CultureInfo.InvariantCulture), currency, false) }, errors);
        Assert.Contains("eligibilityPolicy.projectBudgetLimit", errors.Keys);
    }

    [Fact]
    public void Other_and_empty_manual_items_cannot_confirm_eligibility()
    {
        var errors = new FieldValidationErrors();
        FundingEligibilityPolicyRules.Validate(Policy with
        { RequiredCategoryIds = [16], RequiredBeneficiaryTypeIds = [12], ManualRequirements = [" "] }, errors);
        Assert.Equal(3, errors.Count);
    }

    [Fact]
    public void Migration_and_transactional_acceptance_parse_as_Azure_SQL()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var scripts = new[] { SqlScriptCatalog.DiscoverMigrations(root).Single(x => x.Sequence == 64),
                              SqlScriptCatalog.DiscoverTests(root).Single(x => x.Sequence == 64) };
        foreach (var batch in scripts.SelectMany(x => x.Batches))
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.Empty(errors);
        }
    }
}
