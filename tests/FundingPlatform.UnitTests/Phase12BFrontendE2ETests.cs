using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase12BFrontendE2ETests
{
    [Fact]
    public void Public_browser_suite_is_deterministic_accessible_and_runs_in_ci()
    {
        var package = Read("frontend", "funding-platform-web", "package.json");
        var config = Read("frontend", "funding-platform-web", "playwright.config.ts");
        var suite = Read("frontend", "funding-platform-web", "e2e", "public.spec.ts");
        var vite = Read("frontend", "funding-platform-web", "vite.config.ts");
        var ci = Read(".github", "workflows", "ci.yml");

        Assert.Contains("test:e2e:public", package, StringComparison.Ordinal);
        Assert.Contains("typecheck:e2e", package, StringComparison.Ordinal);
        Assert.Contains("failOnFlakyTests", config, StringComparison.Ordinal);
        Assert.Contains("VITE_API_BASE_URL: '/api/v1'", config, StringComparison.Ordinal);
        Assert.Contains("FUNDING_PLATFORM_API_PROXY_TARGET: 'http://127.0.0.1:9'", config,
            StringComparison.Ordinal);
        Assert.Contains("video: 'off'", config, StringComparison.Ordinal);
        Assert.Contains("AxeBuilder", suite, StringComparison.Ordinal);
        Assert.Contains("**/api/v1/**", suite, StringComparison.Ordinal);
        Assert.Contains("unexpectedApiRequests", suite, StringComparison.Ordinal);
        Assert.Contains("/dashboard", suite, StringComparison.Ordinal);
        Assert.Contains("/admin", suite, StringComparison.Ordinal);
        Assert.Contains("/funding", suite, StringComparison.Ordinal);
        Assert.Contains("deploy-meta.json", suite, StringComparison.Ordinal);
        Assert.Contains("include: ['src/**/*.test.{ts,tsx}']", vite, StringComparison.Ordinal);
        Assert.Contains("npx playwright install --with-deps chromium", ci, StringComparison.Ordinal);
        Assert.Contains("npm run test:e2e:public", ci, StringComparison.Ordinal);
        Assert.DoesNotContain("azure/login", ci, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Azure_public_browser_job_has_no_cloud_or_user_credentials()
    {
        var workflow = Read(".github", "workflows", "frontend-dev.yml");
        var jobStart = workflow.IndexOf("\n  public_e2e:", StringComparison.Ordinal);

        Assert.True(jobStart >= 0);
        var publicJob = workflow[jobStart..];
        Assert.Contains("needs: [resolve_targets, deploy]", publicJob, StringComparison.Ordinal);
        Assert.Contains("permissions:\n      contents: read", publicJob, StringComparison.Ordinal);
        Assert.Contains("PLAYWRIGHT_BASE_URL", publicJob, StringComparison.Ordinal);
        Assert.Contains("E2E_EXPECTED_RELEASE_SHA", publicJob, StringComparison.Ordinal);
        Assert.DoesNotContain("id-token: write", publicJob, StringComparison.Ordinal);
        Assert.DoesNotContain("azure/login", publicJob, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SWA_DEPLOYMENT_TOKEN", publicJob, StringComparison.Ordinal);
        Assert.DoesNotContain("secrets.", publicJob, StringComparison.Ordinal);
        Assert.DoesNotContain("environment:", publicJob, StringComparison.Ordinal);
    }

    [Fact]
    public void Optional_authenticated_suite_is_fail_closed_and_does_not_capture_sessions()
    {
        var suite = Read("frontend", "funding-platform-web", "e2e", "authenticated.spec.ts");
        var ignore = Read(".gitignore");

        Assert.Contains("E2E_USER_EMAIL", suite, StringComparison.Ordinal);
        Assert.Contains("E2E_USER_PASSWORD", suite, StringComparison.Ordinal);
        Assert.Contains("E2E_ALLOWED_ORIGINS", suite, StringComparison.Ordinal);
        Assert.Contains("E2E_ALLOWED_API_ORIGINS", suite, StringComparison.Ordinal);
        Assert.Contains("target.protocol !== 'https:'", suite, StringComparison.Ordinal);
        Assert.Contains("target.origin !== value", suite, StringComparison.Ordinal);
        Assert.Contains("target.username", suite, StringComparison.Ordinal);
        Assert.Contains("request.method() !== 'POST'", suite, StringComparison.Ordinal);
        Assert.Contains("/api/v1/auth/login", suite, StringComparison.Ordinal);
        Assert.Contains("route.abort('blockedbyclient')", suite, StringComparison.Ordinal);
        Assert.Contains("screenshot: 'off', trace: 'off', video: 'off'", suite,
            StringComparison.Ordinal);
        Assert.Contains("test.skip(!email || !password", suite, StringComparison.Ordinal);
        Assert.DoesNotContain("storageState", suite, StringComparison.Ordinal);
        Assert.DoesNotContain("@gmail", suite, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("SuperAdmin", suite, StringComparison.Ordinal);
        Assert.Contains("**/playwright/.auth/", ignore, StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
