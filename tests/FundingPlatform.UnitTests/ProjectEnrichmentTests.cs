using FundingPlatform.Application.Projects;
using FundingPlatform.Core.Projects;
using FundingPlatform.Core.Validation;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;

namespace FundingPlatform.UnitTests;

public sealed class ProjectEnrichmentTests
{
    [Fact]
    public void Empty_optional_data_is_valid_and_does_not_invent_values()
    {
        var errors = new FieldValidationErrors();
        ProjectEnrichmentRules.Validate(null, errors);
        var value = ProjectEnrichmentRules.Normalize(new());
        ProjectEnrichmentRules.Validate(value, errors);
        Assert.Empty(errors);
        Assert.Null(value!.BeneficiaryCount);
        Assert.Null(value.SeekingConsortium);
        Assert.Empty(value.ImpactIndicators!);
        Assert.Equal(ProjectLocationVisibility.RegionOnly, value.LocationVisibility);
    }

    [Fact]
    public void Normalization_trims_content_without_changing_measurements_or_coordinates()
    {
        var value = ProjectEnrichmentRules.Normalize(new(
            Problem: "  Acceso al agua  ", Solution: " ", Locality: "  Comuna  ",
            Latitude: -33.456789m, Longitude: -70.654321m, BeneficiaryCount: 0,
            ImpactIndicators: [new(" Emisiones ", " tCO2 ", 100, -5)],
            SoughtPartners: "  Municipios ", SeekingConsortium: false));
        Assert.Equal("Acceso al agua", value!.Problem);
        Assert.Null(value.Solution);
        Assert.Equal(-33.456789m, value.Latitude);
        Assert.Equal("Emisiones", value.ImpactIndicators![0]!.Name);
        Assert.Equal(-5, value.ImpactIndicators[0]!.Target);
        var errors = new FieldValidationErrors();
        ProjectEnrichmentRules.Validate(value, errors);
        Assert.Empty(errors);
    }

    public static TheoryData<ProjectEnrichment, string, string> InvalidValues => new()
    {
        { new(Problem: new string('x', 3001)), "enrichment.problem", "text-max-length" },
        { new(Solution: new string('x', 3001)), "enrichment.solution", "text-max-length" },
        { new(Locality: new string('x', 201)), "enrichment.locality", "text-max-length" },
        { new(SoughtPartners: new string('x', 2001)), "enrichment.soughtPartners", "text-max-length" },
        { new(SoughtProfessionals: new string('x', 2001)), "enrichment.soughtProfessionals", "text-max-length" },
        { new(BeneficiaryCount: -1), "enrichment.beneficiaryCount", "project-beneficiary-count-invalid" },
        { new(Latitude: 0), "enrichment.latitude", "project-coordinate-pair-required" },
        { new(Longitude: 0), "enrichment.latitude", "project-coordinate-pair-required" },
        { new(Latitude: 90.01m, Longitude: 0), "enrichment.latitude", "project-latitude-invalid" },
        { new(Latitude: 0, Longitude: -180.01m), "enrichment.longitude", "project-longitude-invalid" },
        { new(LocationVisibility: (ProjectLocationVisibility)255), "enrichment.locationVisibility", "project-location-visibility-invalid" },
        { new(LocationVisibility: ProjectLocationVisibility.Locality), "enrichment.locality", "project-locality-required" },
        { new(LocationVisibility: ProjectLocationVisibility.ApproximatePoint), "enrichment.latitude", "project-public-point-required" },
        { new(ImpactIndicators: [null]), "enrichment.impactIndicators.0", "project-indicator-fields-required" },
        { new(ImpactIndicators: [new("Indicator", null)]), "enrichment.impactIndicators.0", "project-indicator-fields-required" },
        { new(ImpactIndicators: [new(new string('x', 201), "people")]), "enrichment.impactIndicators.0.name", "text-max-length" },
        { new(ImpactIndicators: [new("Indicator", new string('x', 81))]), "enrichment.impactIndicators.0.unit", "text-max-length" },
        { new(ImpactIndicators: [new("Indicator", "people", decimal.MaxValue)]), "enrichment.impactIndicators.0.baseline", "project-indicator-measurement-invalid" },
        { new(ImpactIndicators: [new("Indicator", "people", Target: decimal.MinValue)]), "enrichment.impactIndicators.0.target", "project-indicator-measurement-invalid" },
        { new(ImpactIndicators: Enumerable.Repeat<ProjectImpactIndicator?>(new("Indicator", "people"), 21).ToArray()), "enrichment.impactIndicators", "project-indicators-limit" }
    };

    [Theory]
    [MemberData(nameof(InvalidValues))]
    public void Invalid_data_produces_stable_field_codes(ProjectEnrichment value, string field, string code)
    {
        var errors = new FieldValidationErrors();
        ProjectEnrichmentRules.Validate(ProjectEnrichmentRules.Normalize(value), errors);
        Assert.Equal(code, Assert.Single(errors.Issues[field]).Code);
    }

    [Theory]
    [InlineData(0, false, false)]
    [InlineData(1, true, false)]
    [InlineData(2, true, true)]
    [InlineData(255, false, false)]
    public void Public_projection_is_opt_in_and_never_mutates_private_content(byte visibility, bool locality, bool point)
    {
        var original = new ProjectEnrichment(Problem: "Public problem", Locality: "Private locality",
            Latitude: -33.455m, Longitude: 70.655m, LocationVisibility: (ProjectLocationVisibility)visibility);
        var result = original.ForPublic();
        Assert.Equal(locality ? "Private locality" : null, result.Locality);
        Assert.Equal(point ? -33.46m : null, result.Latitude);
        Assert.Equal(point ? 70.66m : null, result.Longitude);
        Assert.Equal("Public problem", result.Problem);
        Assert.Equal(-33.455m, original.Latitude);
        Assert.Equal(result, result.ForPublic());
    }

    [Fact]
    public void Public_projection_fails_closed_for_partial_or_out_of_range_points()
    {
        foreach (var value in new[]
        {
            new ProjectEnrichment(Latitude: 1, LocationVisibility: ProjectLocationVisibility.ApproximatePoint),
            new ProjectEnrichment(Latitude: 100, Longitude: 1, LocationVisibility: ProjectLocationVisibility.ApproximatePoint)
        })
        {
            Assert.Null(value.ForPublic().Latitude);
            Assert.Null(value.ForPublic().Longitude);
        }
    }

    [Fact]
    public void Migration_and_smoke_parse_as_Azure_SQL_and_preserve_security_boundaries()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = SqlScriptCatalog.DiscoverMigrations(root).Single(script => script.Sequence == 40);
        var smoke = SqlScriptCatalog.DiscoverTests(root).Single(script => script.Sequence == 40);
        var workflowSmoke = SqlScriptCatalog.DiscoverTests(root).Single(script => script.Sequence == 8);
        foreach (var script in new[] { migration, smoke, workflowSmoke })
        foreach (var batch in script.Batches)
        {
            using var reader = new StringReader(batch);
            _ = new TSql170Parser(true, SqlEngineType.SqlAzure).Parse(reader, out var errors);
            Assert.True(errors.Count == 0, string.Join("; ", errors.Select(error => $"{error.Line}: {error.Message}")));
        }
        var sql = File.ReadAllText(Path.Combine(root, "database", "Migrations", migration.FileName));
        Assert.Contains("THROW 51411, N'Legacy update cannot replace a project with enrichment data.'", sql);
        Assert.Contains("Project enrichment must match its version snapshot", sql);
        Assert.Contains("WHERE Id = @ProjectId AND RowVersion = @ExpectedRowVersion", sql);
        Assert.Contains("Only draft or rejected project content can be edited", sql);
        Assert.Contains("INNER JOIN dbo.FundingPlatform_ifn_ProjectMarketplaceReady()", sql);
        Assert.DoesNotContain("CREATE OR ALTER FUNCTION", sql);
        Assert.DoesNotContain("GRANT ", sql);
        Assert.Contains("ELSE NULL END", sql); // existing stage semantics remain
        var publicSql = sql[sql.IndexOf("CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_ProjectMarketplace_GetBySlug", StringComparison.Ordinal)..];
        Assert.DoesNotContain("\n           projects.EnrichmentJson,", publicSql);
        Assert.Contains("ROUND(TRY_CONVERT", publicSql);
        Assert.Contains("FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES", publicSql);
        var legacySmoke = File.ReadAllText(Path.Combine(root, "database", "Tests", workflowSmoke.FileName));
        Assert.Contains("EnrichmentJson NVARCHAR(MAX)", legacySmoke);
        Assert.Contains("ProjectStatus TINYINT, ProjectStage TINYINT, PublicationStatus TINYINT", legacySmoke);
        Assert.Contains("SustainableDevelopmentGoalsJson NVARCHAR(MAX)", legacySmoke);
    }
}
