using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase12AInfrastructureTests
{
    [Fact]
    public void Infrastructure_is_dev_only_identity_based_and_cost_bounded()
    {
        var main = Read("infra", "main.bicep");
        var environment = Read("infra", "modules", "environment.bicep");
        var containerApi = Read("infra", "modules", "container-api.bicep");
        var functions = Read("infra", "modules", "flex-function.bicep");

        Assert.Contains("@allowed(['dev'])", main, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Consumption/budgets", main, StringComparison.Ordinal);
        Assert.Contains("GP_S_Gen5_1", environment, StringComparison.Ordinal);
        Assert.Contains("autoPauseDelay: 60", environment, StringComparison.Ordinal);
        Assert.Contains("Microsoft.App/managedEnvironments", environment, StringComparison.Ordinal);
        Assert.Contains("Microsoft.ContainerRegistry/registries", environment, StringComparison.Ordinal);
        Assert.Contains("sku: { name: 'Basic'", environment, StringComparison.Ordinal);
        Assert.Contains("Microsoft.App/containerApps", containerApi, StringComparison.Ordinal);
        Assert.Contains("minReplicas: minReplicas", containerApi, StringComparison.Ordinal);
        Assert.Contains("maxReplicas: 1", containerApi, StringComparison.Ordinal);
        Assert.Contains("memory: '1Gi'", containerApi, StringComparison.Ordinal);
        Assert.Contains("path: '/health'", containerApi, StringComparison.Ordinal);
        Assert.DoesNotContain("/health/ready", containerApi, StringComparison.Ordinal);
        Assert.Contains("tier: 'FlexConsumption'", functions, StringComparison.Ordinal);
        Assert.Contains("allowSharedKeyAccess: false", environment, StringComparison.Ordinal);
        Assert.Contains("allowSharedKeyAccess: false", functions, StringComparison.Ordinal);
        Assert.Contains("Storage Queue Data Message Sender", Read("docs", "AZURE-MVP-DEPLOYMENT.md"), StringComparison.Ordinal);
        Assert.DoesNotContain("listKeys(", main + environment + containerApi + functions, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("AccountKey", main + environment + containerApi + functions, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Dangerous_integrations_ship_disabled_and_secrets_are_not_parameters()
    {
        var environment = Read("infra", "modules", "environment.bicep");
        var example = Read("infra", "dev.parameters.example.json");
        foreach (var setting in new[] { "DEFENDER_EVENT_GRID_ENABLED", "OFFICIAL_RSS_ENABLED", "SEMANTIC_ENABLED", "OPENAI_ENABLED", "ALERTS_ENABLED", "BILLING_ENABLED" })
            Assert.Contains($"{setting}: 'false'", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("accessToken", example, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("clientSecret", example, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("password", example, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Deployment_is_manual_oidc_preflighted_and_apply_requires_confirmation()
    {
        var workflow = Read(".github", "workflows", "infra-dev.yml");
        var validation = Read(".github", "workflows", "infra-validate.yml");
        var script = Read("infra", "scripts", "deploy-dev.sh");
        Assert.Contains("workflow_dispatch", workflow, StringComparison.Ordinal);
        Assert.Contains("id-token: write", workflow, StringComparison.Ordinal);
        Assert.Contains("azure/login@v2", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("push:", workflow, StringComparison.Ordinal);
        Assert.Contains("DEPLOY-DEV", workflow, StringComparison.Ordinal);
        Assert.Contains("list-flexconsumption-runtimes", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.App", script, StringComparison.Ordinal);
        Assert.Contains("az acr build", script, StringComparison.Ordinal);
        Assert.Contains("apply-base", script, StringComparison.Ordinal);
        Assert.Contains("DEPLOY-DEV-BASE", script, StringComparison.Ordinal);
        Assert.Contains("deployApiContainer=false", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_API_MIN_REPLICAS", script, StringComparison.Ordinal);
        Assert.Contains("deployment sub what-if", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_APPLY_CONFIRMATION", script, StringComparison.Ordinal);
        Assert.Contains("bicep build", validation, StringComparison.Ordinal);
    }

    [Fact]
    public void Api_container_is_non_root_private_and_managed_identity_only()
    {
        var dockerfile = Read("src", "FundingPlatform.Api", "Dockerfile");
        var dockerIgnore = Read(".dockerignore");
        var environment = Read("infra", "modules", "environment.bicep");
        var apiProgram = Read("src", "FundingPlatform.Api", "Program.cs");

        Assert.Contains("USER $APP_UID", dockerfile, StringComparison.Ordinal);
        Assert.Contains("/p:UseAppHost=false", dockerfile, StringComparison.Ordinal);
        Assert.Contains(".env", dockerIgnore, StringComparison.Ordinal);
        Assert.Contains("adminUserEnabled: false", environment, StringComparison.Ordinal);
        Assert.Contains("anonymousPullEnabled: false", environment, StringComparison.Ordinal);
        Assert.Contains("apiAcrPull", environment, StringComparison.Ordinal);
        Assert.Contains("AZURE_CLIENT_ID: apiIdentity.properties.clientId", environment, StringComparison.Ordinal);
        Assert.Contains("AzureRuntimeCredentialFactory.Create", apiProgram, StringComparison.Ordinal);
        Assert.Contains("UserAssignedManagedIdentitySqlConnectionFactory", apiProgram, StringComparison.Ordinal);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
