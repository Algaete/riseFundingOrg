using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase8BArchitectureTests
{
    [Fact]
    public void Migration_freezes_publication_tenant_idempotency_and_currency_guards()
    {
        var migration = Read(
            "database",
            "Migrations",
            "019_project_marketplace_applications_calendar.sql");

        Assert.Contains(
            "CREATE OR ALTER FUNCTION dbo.FundingPlatform_ifn_ProjectMarketplaceReady",
            migration,
            StringComparison.Ordinal);
        Assert.Contains("projects.PublicationStatus = 2", migration, StringComparison.Ordinal);
        Assert.Contains("projects.IsActive = 1", migration, StringComparison.Ordinal);
        Assert.Contains("organizations.ProfileStatus = 2", migration, StringComparison.Ordinal);
        Assert.Contains(
            "FundingPlatform_UQ_FundingApplications_OrganizationProjectOpportunity",
            migration,
            StringComparison.Ordinal);
        Assert.Contains("IdempotencyKeyHash BINARY(32) NOT NULL", migration, StringComparison.Ordinal);
        Assert.Contains("RequestHash BINARY(32) NOT NULL", migration, StringComparison.Ordinal);
        Assert.Contains("Notes NVARCHAR(MAX) NULL", migration, StringComparison.Ordinal);
        Assert.Contains("DATALENGTH(Notes) <= 10000", migration, StringComparison.Ordinal);
        Assert.Equal(
            2,
            migration.Split(
                "DATALENGTH(@NormalizedNotes) > 10000",
                StringSplitOptions.None).Length - 1);
        Assert.DoesNotContain("NVARCHAR(5000)", migration, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("WITH (UPDLOCK, HOLDLOCK)", migration, StringComparison.Ordinal);
        Assert.Contains(
            "@NormalizedSort = N'funding-gap-desc' AND @NormalizedCurrency IS NULL",
            migration,
            StringComparison.Ordinal);
        Assert.Contains(
            "applications.OwnerUserId = @UserId OR @MembershipRole = 1",
            migration,
            StringComparison.Ordinal);
        Assert.Contains(
            "DATEDIFF(DAY, @FromDate, @ToDate) > 365",
            migration,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Public_organization_projection_is_allowlisted_and_bounded()
    {
        var migration = Read(
            "database",
            "Migrations",
            "019_project_marketplace_applications_calendar.sql");
        var start = migration.IndexOf(
            "CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_OrganizationMarketplace_Get",
            StringComparison.Ordinal);
        var end = migration.IndexOf(
            "CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingApplication_Create",
            start,
            StringComparison.Ordinal);
        var procedure = migration[start..end];

        Assert.Contains("SELECT TOP (50) projects.PublicId", procedure, StringComparison.Ordinal);
        Assert.DoesNotContain("TaxIdentifier", procedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("LegalName", procedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("AnnualBudget", procedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DesiredFunding", procedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Email", procedure, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Verified", procedure, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Smoke_acknowledges_every_successful_application_event()
    {
        var smoke = Read(
            "database",
            "Tests",
            "019_project_marketplace_applications_calendar_smoke.sql");

        Assert.Contains("IF @AcknowledgedCount <> 6", smoke, StringComparison.Ordinal);
        Assert.DoesNotContain("IF @AcknowledgedCount <> 5", smoke, StringComparison.Ordinal);
        Assert.Contains(
            "DATEADD(SECOND, 1, SYSUTCDATETIME())",
            smoke,
            StringComparison.Ordinal);
        Assert.Contains(
            "DATEADD(SECOND, 1, @FirstAckAtUtc)",
            smoke,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Sql_repositories_materialize_datetime_before_datetimeoffset()
    {
        var marketplace = Read(
            "src",
            "FundingPlatform.Infrastructure",
            "Persistence",
            "Marketplace",
            "SqlMarketplaceRepository.cs");
        var applications = Read(
            "src",
            "FundingPlatform.Infrastructure",
            "Persistence",
            "Applications",
            "SqlFundingApplicationRepository.cs");

        Assert.Contains("DateTime.SpecifyKind", marketplace, StringComparison.Ordinal);
        Assert.Contains("DateTime.SpecifyKind", applications, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "public DateTimeOffset PublishedAtUtc",
            marketplace,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "public DateTimeOffset CreatedAtUtc",
            applications,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Phase_8b_does_not_introduce_matching_ai_alerts_or_networking()
    {
        var files = new[]
        {
            Read("src", "FundingPlatform.Application", "Marketplace", "MarketplaceService.cs"),
            Read("src", "FundingPlatform.Application", "Applications", "FundingApplicationService.cs"),
            Read("src", "FundingPlatform.Api", "Endpoints", "MarketplaceEndpoints.cs"),
            Read("src", "FundingPlatform.Api", "Endpoints", "FundingApplicationEndpoints.cs")
        };

        foreach (var source in files)
        {
            Assert.DoesNotContain("OpenAI", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Embedding", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("MatchScore", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("ConnectionRequest", source, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("SendAlert", source, StringComparison.OrdinalIgnoreCase);
        }
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
