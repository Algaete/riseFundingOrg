using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase10AArchitectureTests
{
    [Fact]
    public void Saved_searches_are_private_tenant_scoped_and_reuse_the_8a_filter_contract()
    {
        var migration = Read("database", "Migrations", "024_saved_search_alerts.sql");
        var endpoints = Read(
            "src", "FundingPlatform.Api", "Endpoints", "SavedSearchAlertEndpoints.cs");

        Assert.Contains("FundingPlatform_SavedSearchCreateRequests", migration,
            StringComparison.Ordinal);
        Assert.Contains("@IdempotencyKeyHash BINARY(32)", migration,
            StringComparison.Ordinal);
        Assert.Contains("@RequestHash BINARY(32)", migration, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_ifn_FundingOpportunityPublicReady()", migration,
            StringComparison.Ordinal);
        Assert.Contains("EligibilityMode = 1", migration, StringComparison.Ordinal);
        Assert.Contains("GeographicScope = 2", migration, StringComparison.Ordinal);
        Assert.Contains("RequireAuthorization(\"full-session\")", endpoints,
            StringComparison.Ordinal);
        Assert.Contains("Idempotency-Key", endpoints, StringComparison.Ordinal);
        Assert.Contains("IfMatch", endpoints, StringComparison.Ordinal);
        Assert.Contains("Status412PreconditionFailed", endpoints, StringComparison.Ordinal);
        Assert.Contains("Status428PreconditionRequired", endpoints, StringComparison.Ordinal);
    }

    [Fact]
    public void Alert_delivery_is_disabled_by_default_bounded_and_does_not_persist_email_content()
    {
        var migration = Read("database", "Migrations", "024_saved_search_alerts.sql");
        var options = Read(
            "src", "FundingPlatform.Infrastructure", "Configuration", "AlertOptions.cs");
        var sender = Read(
            "src", "FundingPlatform.Infrastructure", "Notifications",
            "AlertEmailSenders.cs");
        var env = Read(".env.example");
        var logs = CreateTable(migration, "FundingPlatform_NotificationLogs");
        var subscriptions = CreateTable(migration, "FundingPlatform_AlertSubscriptions");

        Assert.Contains("public bool Enabled", options, StringComparison.Ordinal);
        Assert.Contains("ALERTS_ENABLED=\"false\"", env, StringComparison.Ordinal);
        Assert.Contains("WaitUntil.Started", sender, StringComparison.Ordinal);
        Assert.Contains("provider-response-uncertain", sender, StringComparison.Ordinal);
        Assert.Contains("/alerts/unsubscribe#token=", sender, StringComparison.Ordinal);
        Assert.DoesNotContain("/alerts/unsubscribe?token=", sender, StringComparison.Ordinal);
        Assert.Contains("WebUtility.HtmlEncode", sender, StringComparison.Ordinal);
        Assert.DoesNotContain("Email", logs, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Body", logs, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Raw", logs, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Token", subscriptions, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("UnsubscribeNonce", subscriptions, StringComparison.Ordinal);
        Assert.Contains("Status = CASE WHEN @DeliveryUnknown = 1 THEN 4", migration,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Worker_has_sp_only_permissions_leases_and_no_email_in_timer_payloads()
    {
        var migration = Read("database", "Migrations", "024_saved_search_alerts.sql");
        var functions = Read(
            "src", "FundingPlatform.Workers", "Functions", "AlertProcessingFunctions.cs");
        var program = Read("src", "FundingPlatform.Workers", "Program.cs");

        Assert.Contains("FundingPlatform_AlertWorkerRole", migration, StringComparison.Ordinal);
        Assert.Contains("GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertSchedule_Claim",
            migration, StringComparison.Ordinal);
        Assert.Contains("GRANT EXECUTE ON OBJECT::dbo.FundingPlatform_usp_AlertDelivery_Complete",
            migration, StringComparison.Ordinal);
        Assert.Contains("DENY SELECT, INSERT, UPDATE, DELETE", migration,
            StringComparison.Ordinal);
        Assert.Contains("LeaseId", migration, StringComparison.Ordinal);
        Assert.Contains("AttemptCount", migration, StringComparison.Ordinal);
        Assert.Contains("NextRunAtUtc < DATEADD(HOUR, -24, @NowUtc)", migration,
            StringComparison.Ordinal);
        Assert.Contains("AND LeaseUntilUtc > @NowUtc", migration,
            StringComparison.Ordinal);
        Assert.Contains("TimerTrigger(\"15 */5 * * * *\")", functions,
            StringComparison.Ordinal);
        Assert.Contains("TimerTrigger(\"35 */1 * * * *\")", functions,
            StringComparison.Ordinal);
        Assert.Contains("AzureCommunicationAlertEmailSender", program,
            StringComparison.Ordinal);
        Assert.Contains("DevelopmentAlertEmailSender", program, StringComparison.Ordinal);
        Assert.DoesNotContain("RecipientEmail", functions, StringComparison.Ordinal);
    }

    [Fact]
    public void Smoke_exercises_tenant_idempotency_digest_retry_unsubscribe_and_rollback()
    {
        var smoke = Read("database", "Tests", "024_saved_search_alerts_smoke.sql");

        Assert.Contains("BEGIN TRY", smoke, StringComparison.Ordinal);
        Assert.Contains("BEGIN CATCH", smoke, StringComparison.Ordinal);
        Assert.Contains("ROLLBACK", smoke, StringComparison.Ordinal);
        Assert.Contains("Cross-tenant saved search", smoke, StringComparison.Ordinal);
        Assert.Contains("idempotent replay", smoke, StringComparison.Ordinal);
        Assert.Contains("AlertSchedule_Materialize", smoke, StringComparison.Ordinal);
        Assert.Contains("AlertDelivery_RenewLease", smoke, StringComparison.Ordinal);
        Assert.Contains("AlertDelivery_Fail", smoke, StringComparison.Ordinal);
        Assert.Contains("AlertDelivery_Complete", smoke, StringComparison.Ordinal);
        Assert.Contains("AlertSubscription_Unsubscribe", smoke, StringComparison.Ordinal);
        Assert.Contains("FundingPlatform_AlertWorkerRole", smoke, StringComparison.Ordinal);
    }

    private static string CreateTable(string script, string table)
    {
        var start = script.IndexOf($"CREATE TABLE dbo.{table}", StringComparison.Ordinal);
        Assert.True(start >= 0, $"Table {table} was not found.");
        var end = script.IndexOf("\nGO", start, StringComparison.Ordinal);
        Assert.True(end > start, $"Table {table} has no batch terminator.");
        return script[start..end];
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
