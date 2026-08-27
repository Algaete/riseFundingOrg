using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase10BArchitectureTests
{
    [Fact]
    public void Networking_is_opt_in_marketplace_safe_and_contains_no_member_pii()
    {
        var migration = Read("database", "Migrations", "025_organization_networking.sql");
        var directory = Procedure(migration, "FundingPlatform_usp_OrganizationNetworkDirectory_Search");

        Assert.Contains("IsDiscoverable", migration, StringComparison.Ordinal);
        Assert.Contains("AllowRequests", migration, StringComparison.Ordinal);
        Assert.Contains("END) AS [Exists],", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("END) AS Exists,", migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ifn_OrganizationMarketplaceReady()", directory, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ifn_ProjectMarketplaceReady()", directory, StringComparison.Ordinal);
        Assert.Contains("blocked.Status = 4", directory, StringComparison.Ordinal);
        Assert.DoesNotContain("Email", directory, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("TaxIdentifier", directory, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("LegalName", directory, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Mutations_are_admin_moderated_idempotent_versioned_and_bounded()
    {
        var migration = Read("database", "Migrations", "025_organization_networking.sql");
        var create = Procedure(migration, "FundingPlatform_usp_OrganizationConnection_Create");
        var action = Procedure(migration, "FundingPlatform_usp_OrganizationConnection_Action");

        Assert.Contains("@Role <> 1", create, StringComparison.Ordinal);
        Assert.Contains("IdempotencyKeyHash BINARY(32)", migration, StringComparison.Ordinal);
        Assert.Contains("RequestHash BINARY(32)", migration, StringComparison.Ordinal);
        Assert.Contains("DATEADD(HOUR, -24, @NowUtc)", create, StringComparison.Ordinal);
        Assert.Contains(">= 5", create, StringComparison.Ordinal);
        Assert.Contains("@RowVersion <> @ExpectedRowVersion", action, StringComparison.Ordinal);
        Assert.Contains("Status IN (0, 1)", migration, StringComparison.Ordinal);
        Assert.Contains("OrganizationConnectionRequests_Lifecycle", migration, StringComparison.Ordinal);
        Assert.Contains("OrganizationConnectionCreateRequests_Immutable", migration, StringComparison.Ordinal);
        Assert.Contains("SET XACT_ABORT OFF", migration, StringComparison.Ordinal);
        Assert.DoesNotContain("chat", migration, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Api_is_private_no_store_rate_limited_and_has_no_public_connection_route()
    {
        var endpoints = Read("src", "FundingPlatform.Api", "Endpoints", "NetworkingEndpoints.cs");
        var program = Read("src", "FundingPlatform.Api", "Program.cs");
        var middleware = Read("src", "FundingPlatform.Api", "Middleware", "SecurityHeadersMiddleware.cs");

        Assert.Contains("RequireAuthorization(\"full-session\")", endpoints, StringComparison.Ordinal);
        Assert.Contains("network-connect-write", endpoints, StringComparison.Ordinal);
        Assert.Contains("Idempotency-Key", endpoints, StringComparison.Ordinal);
        Assert.Contains("IfMatch", endpoints, StringComparison.Ordinal);
        Assert.Contains("PermitLimit = 5", program, StringComparison.Ordinal);
        Assert.Contains("no-store", middleware, StringComparison.Ordinal);
        Assert.DoesNotContain("/api/v1/marketplace/connections", endpoints, StringComparison.Ordinal);
    }

    [Fact]
    public void Smoke_exercises_opt_in_replay_accept_block_privacy_and_rollback()
    {
        var smoke = Read("database", "Tests", "025_organization_networking_smoke.sql");
        Assert.Contains("BEGIN TRY", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK", smoke, StringComparison.Ordinal);
        Assert.Contains("OrganizationNetworkDirectory_Search", smoke, StringComparison.Ordinal);
        Assert.Contains("idempotent replay", smoke, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("@ActionCode = 1", smoke, StringComparison.Ordinal);
        Assert.Contains("@ActionCode = 4", smoke, StringComparison.Ordinal);
        Assert.Contains("Private member contact data", smoke, StringComparison.Ordinal);
    }

    private static string Procedure(string script, string procedure)
    {
        var start = script.IndexOf($"CREATE OR ALTER PROCEDURE dbo.{procedure}", StringComparison.Ordinal);
        Assert.True(start >= 0, $"Procedure {procedure} was not found.");
        var end = script.IndexOf("\nGO", start, StringComparison.Ordinal);
        Assert.True(end > start);
        return script[start..end];
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
