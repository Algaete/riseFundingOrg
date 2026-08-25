using System.Reflection;
using FundingPlatform.Core.Matching;
using FundingPlatform.Infrastructure.Persistence.Matching;

namespace FundingPlatform.UnitTests;

public sealed class ProjectMatchingMaterializationTests
{
    [Fact]
    public void No_minimum_operating_years_reason_is_allowlisted()
    {
        var method = typeof(SqlProjectMatchingRepository).GetMethod(
            "NormalizeReasonCode",
            BindingFlags.NonPublic | BindingFlags.Static)!;

        Assert.Equal(
            "operating_years.not_required",
            method.Invoke(null, ["operating_years.not_required"]));
    }

    [Fact]
    public void Reason_parameters_keep_only_typed_allowlisted_values()
    {
        var method = typeof(SqlProjectMatchingRepository).GetMethod(
            "ParseReasonParameters",
            BindingFlags.NonPublic | BindingFlags.Static)!;
        var result = Assert.IsAssignableFrom<IReadOnlyDictionary<string, string?>>(
            method.Invoke(null,
            [
                """
                {
                  "matchCount":"2",
                  "projectCurrency":"USD",
                  "requiredYears":"3",
                  "taxIdentifier":"12.345.678-9",
                  "opportunityCurrency":"person@example.org",
                  "minimumGuaranteedYears":"not-a-number"
                }
                """
            ]));

        Assert.Equal("2", result["matchCount"]);
        Assert.Equal("USD", result["projectCurrency"]);
        Assert.Equal("3", result["requiredYears"]);
        Assert.DoesNotContain("taxIdentifier", result);
        Assert.DoesNotContain("opportunityCurrency", result);
        Assert.DoesNotContain("minimumGuaranteedYears", result);
    }

    [Fact]
    public void Evidence_keeps_only_catalogued_non_pii_value_codes()
    {
        var method = typeof(SqlProjectMatchingRepository).GetMethod(
            "ParseEvidence",
            BindingFlags.NonPublic | BindingFlags.Static)!;
        var result = Assert.IsType<MatchingRuleEvidence>(method.Invoke(null,
        [
            """
            {
              "source":"versioned-snapshots",
              "fieldCode":"geography",
              "valueCodes":["project-geography","12.345.678-9","person@example.org"]
            }
            """
        ]));

        Assert.Equal("versioned-snapshots", result.Source);
        Assert.Equal("geography", result.FieldCode);
        Assert.Equal(["project-geography"], result.ValueCodes);

        var rejected = method.Invoke(null,
        [
            """
            {
              "source":"versioned-snapshots",
              "fieldCode":"geography",
              "valueCodes":["12.345.678-9","person@example.org"]
            }
            """
        ]);
        Assert.Null(rejected);
    }
}
