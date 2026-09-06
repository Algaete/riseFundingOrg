using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase12BOperationalAlertTests
{
    [Fact]
    public void Operational_alerts_are_explicit_opt_in_and_reuse_the_secure_budget_contact()
    {
        var main = Read("infra", "main.bicep");
        var environment = Read("infra", "modules", "environment.bicep");
        var parameters = Read("infra", "dev.parameters.example.json");
        var workflow = Read(".github", "workflows", "infra-dev.yml");
        var deploy = Read("infra", "scripts", "deploy-dev.sh");

        Assert.Contains("param deployOperationalAlerts bool = false", main,
            StringComparison.Ordinal);
        Assert.Contains("deployOperationalAlerts: deployOperationalAlerts", main,
            StringComparison.Ordinal);
        Assert.Contains("operationalAlertContactEmail: budgetContactEmail", main,
            StringComparison.Ordinal);
        Assert.Contains("@secure()\nparam operationalAlertContactEmail string", environment,
            StringComparison.Ordinal);
        Assert.Contains("if (deployOperationalAlerts && deployCompute)", environment,
            StringComparison.Ordinal);
        Assert.Contains("\"deployOperationalAlerts\": { \"value\": false }", parameters,
            StringComparison.Ordinal);

        Assert.Contains("deploy_operational_alerts:", workflow, StringComparison.Ordinal);
        Assert.Contains("AZURE_DEPLOY_OPERATIONAL_ALERTS: ${{ inputs.deploy_operational_alerts }}",
            workflow, StringComparison.Ordinal);
        Assert.Contains("deploy_operational_alerts=\"${AZURE_DEPLOY_OPERATIONAL_ALERTS:-false}\"",
            deploy, StringComparison.Ordinal);
        Assert.Contains("deployOperationalAlerts=\"$deploy_operational_alerts\"", deploy,
            StringComparison.Ordinal);
    }

    [Fact]
    public void Availability_probe_is_https_cost_bounded_and_routes_through_one_action_group()
    {
        var alerts = Read("infra", "modules", "operational-alerts.bicep");
        var environment = Read("infra", "modules", "environment.bicep");

        Assert.Contains("Microsoft.Insights/actionGroups@2023-01-01", alerts,
            StringComparison.Ordinal);
        Assert.Contains("emailAddress: contactEmail", alerts, StringComparison.Ordinal);
        Assert.Contains("useCommonAlertSchema: true", alerts, StringComparison.Ordinal);
        Assert.DoesNotContain("webhookReceivers", alerts, StringComparison.Ordinal);
        Assert.DoesNotContain("smsReceivers", alerts, StringComparison.Ordinal);

        Assert.Contains("Microsoft.Insights/webTests@2022-06-15", alerts,
            StringComparison.Ordinal);
        Assert.Contains("RequestUrl: '${apiBaseUrl}/health'", alerts, StringComparison.Ordinal);
        Assert.Contains("HttpVerb: 'GET'", alerts, StringComparison.Ordinal);
        Assert.Contains("ExpectedHttpStatusCode: 200", alerts, StringComparison.Ordinal);
        Assert.Contains("SSLCheck: true", alerts, StringComparison.Ordinal);
        Assert.Contains("SSLCertRemainingLifetimeCheck: 7", alerts, StringComparison.Ordinal);
        Assert.Contains("Frequency: 900", alerts, StringComparison.Ordinal);
        Assert.Contains("Timeout: 30", alerts, StringComparison.Ordinal);
        Assert.Equal(1, alerts.Split("Id: 'us-va-ash-azr'", StringSplitOptions.None).Length - 1);

        Assert.Contains("Microsoft.Insights/metricAlerts@2026-01-01", alerts,
            StringComparison.Ordinal);
        Assert.Contains("Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria", alerts,
            StringComparison.Ordinal);
        Assert.Contains("failedLocationCount: 1", alerts, StringComparison.Ordinal);
        Assert.Contains("windowSize: 'PT15M'", alerts, StringComparison.Ordinal);
        Assert.Contains("actionGroupId: operationsActionGroup.id", alerts,
            StringComparison.Ordinal);
        Assert.Contains("retentionInDays: 30", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("AzureWebJobs", alerts, StringComparison.Ordinal);
    }

    [Fact]
    public void Api_log_alerts_are_aggregated_role_scoped_and_rate_limited()
    {
        var alerts = Read("infra", "modules", "operational-alerts.bicep");

        Assert.Equal(2, alerts.Split(
            "Microsoft.Insights/scheduledQueryRules@2023-12-01",
            StringSplitOptions.None).Length - 1);
        Assert.Contains("AppRequests", alerts, StringComparison.Ordinal);
        Assert.Contains("ResultCode matches regex '^5[0-9][0-9]$'", alerts,
            StringComparison.Ordinal);
        Assert.Contains("AppExceptions", alerts, StringComparison.Ordinal);
        Assert.Equal(2, alerts.Split(
            "where AppRoleName == 'FundingPlatform.Api'",
            StringSplitOptions.None).Length - 1);
        Assert.Equal(2, alerts.Split(
            "summarize EventCount = sum(ItemCount)",
            StringSplitOptions.None).Length - 1);
        Assert.Equal(2, alerts.Split("metricMeasureColumn: 'EventCount'",
            StringSplitOptions.None).Length - 1);
        Assert.Equal(3, alerts.Split("evaluationFrequency: 'PT5M'",
            StringSplitOptions.None).Length - 1);
        Assert.Equal(2, alerts.Split("muteActionsDuration: 'PT30M'",
            StringSplitOptions.None).Length - 1);
        Assert.DoesNotContain("ExceptionMessage", alerts, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("UserAuthenticatedId", alerts, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Backlog_and_stuck_job_alerts_wait_for_a_reliable_baseline()
    {
        var runbook = Read("docs", "runbooks", "operational-alerts-dev.md");

        Assert.Contains("no está desplegado", runbook, StringComparison.Ordinal);
        Assert.Contains("barrera de **creación**, no un teardown", runbook,
            StringComparison.Ordinal);
        Assert.Contains("al menos siete días representativos", runbook,
            StringComparison.Ordinal);
        Assert.Contains("al menos **dos ubicaciones independientes**", runbook,
            StringComparison.Ordinal);
        Assert.Contains("piloto sigue siendo un gate pendiente", runbook,
            StringComparison.Ordinal);
        Assert.Contains("edad del mensaje más antiguo", runbook, StringComparison.Ordinal);
        Assert.Contains("duración p95/p99", runbook, StringComparison.Ordinal);
        Assert.Contains("Functions siguen sin publicar", runbook, StringComparison.Ordinal);
        Assert.Contains("no modifica ni habilita ninguno de los 16 flags", runbook,
            StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
