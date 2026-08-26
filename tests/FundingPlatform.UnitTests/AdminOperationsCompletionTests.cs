using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class AdminOperationsCompletionTests
{
    [Fact]
    public void Migration_and_smoke_are_forward_only_bounded_and_discoverable()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var migration = File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "028_admin_operations_completion.sql"));
        var smoke = File.ReadAllText(Path.Combine(root, "database", "Tests",
            "028_admin_operations_completion_smoke.sql"));
        var discoveredMigration = Assert.Single(SqlScriptCatalog.DiscoverMigrations(root),
            script => script.Sequence == 28);
        var discoveredTest = Assert.Single(SqlScriptCatalog.DiscoverTests(root),
            script => script.Sequence == 28);

        Assert.Equal(28, discoveredMigration.Sequence);
        Assert.Single(discoveredTest.Batches);
        Assert.Equal(5, GoBatchSplitter.Split(migration).Count);
        Assert.Contains("FundingPlatform_fn_AdminAccessState", migration,
            StringComparison.Ordinal);
        Assert.Contains("@PageSize NOT BETWEEN 1 AND 50", migration,
            StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ApiRuntimeRole", migration,
            StringComparison.Ordinal);
        Assert.Contains("BEGIN TRANSACTION", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK TRANSACTION", smoke, StringComparison.Ordinal);
        Assert.DoesNotContain("DROP TABLE", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("DROP PROCEDURE", migration, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Admin_surface_is_read_only_mfa_bounded_and_sanitized()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var endpoints = File.ReadAllText(Path.Combine(root, "src", "FundingPlatform.Api",
            "Endpoints", "AdminOperationsEndpoints.cs"));
        var migration = File.ReadAllText(Path.Combine(root, "database", "Migrations",
            "028_admin_operations_completion.sql"));
        var repository = File.ReadAllText(Path.Combine(root, "src",
            "FundingPlatform.Infrastructure", "Persistence", "Administration",
            "SqlAdminOperationsRepository.cs"));

        Assert.Contains("RequireAuthorization(\"admin-mfa\")", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("RequireRateLimiting(\"organization-activity-read\")", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("MapGet(\"/organizations\"", endpoints, StringComparison.Ordinal);
        Assert.Contains("MapGet(\"/operational-errors\"", endpoints, StringComparison.Ordinal);
        Assert.DoesNotContain("MapPost", endpoints, StringComparison.Ordinal);
        Assert.DoesNotContain("MapPut", endpoints, StringComparison.Ordinal);
        Assert.DoesNotContain("MapPatch", endpoints, StringComparison.Ordinal);
        Assert.DoesNotContain("MapDelete", endpoints, StringComparison.Ordinal);
        Assert.DoesNotContain("TaxIdentifier", repository, StringComparison.Ordinal);
        Assert.DoesNotContain("PayloadHash", repository, StringComparison.Ordinal);
        Assert.DoesNotContain("ProviderEventId", repository, StringComparison.Ordinal);
        Assert.Contains("La explicación asistida terminó con un fallo permanente", migration,
            StringComparison.Ordinal);
        Assert.DoesNotContain("RawPayload", migration, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SecretReference", migration, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void All_visible_application_shell_placeholders_are_replaced()
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        var appPages = File.ReadAllText(Path.Combine(root, "frontend",
            "funding-platform-web", "src", "pages", "app-pages.tsx"));
        var adminPages = File.ReadAllText(Path.Combine(root, "frontend",
            "funding-platform-web", "src", "pages", "admin-pages.tsx"));
        var router = File.ReadAllText(Path.Combine(root, "frontend",
            "funding-platform-web", "src", "router.tsx"));

        Assert.DoesNotContain("PagePlaceholder", appPages, StringComparison.Ordinal);
        Assert.DoesNotContain("PagePlaceholder", adminPages, StringComparison.Ordinal);
        Assert.Contains("DashboardWorkspacePage", appPages, StringComparison.Ordinal);
        Assert.Contains("AdminOrganizationsWorkspacePage", adminPages, StringComparison.Ordinal);
        Assert.Contains("AdminErrorsWorkspacePage", adminPages, StringComparison.Ordinal);
        Assert.Contains("/admin/organizations/:organizationId", router,
            StringComparison.Ordinal);
    }
}
