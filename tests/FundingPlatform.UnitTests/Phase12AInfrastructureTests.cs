using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase12AInfrastructureTests
{
    [Fact]
    public void Infrastructure_is_dev_only_identity_based_and_cost_bounded()
    {
        var main = Read("infra", "main.bicep");
        var environment = Read("infra", "modules", "environment.bicep");
        var environmentRbac = Read("infra", "modules", "environment-rbac.bicep");
        var containerApi = Read("infra", "modules", "container-api.bicep");
        var functions = Read("infra", "modules", "flex-function.bicep");
        var functionRbac = Read("infra", "modules", "flex-function-rbac.bicep");

        Assert.Contains("@allowed(['dev'])", main, StringComparison.Ordinal);
        Assert.Contains("@minLength(8)", main, StringComparison.Ordinal);
        Assert.Contains("@maxLength(8)", main, StringComparison.Ordinal);
        Assert.DoesNotContain("assert ", main, StringComparison.Ordinal);
        Assert.Contains("Microsoft.Consumption/budgets", main, StringComparison.Ordinal);
        Assert.Contains("GP_S_Gen5_1", environment, StringComparison.Ordinal);
        Assert.Contains("autoPauseDelay: 60", environment, StringComparison.Ordinal);
        Assert.Contains("backupShortTermRetentionPolicies@2023-08-01", environment, StringComparison.Ordinal);
        Assert.Contains("retentionDays: 7", environment, StringComparison.Ordinal);
        Assert.Contains("diffBackupIntervalInHours: 12", environment, StringComparison.Ordinal);
        Assert.Equal(2, environment.Split("maximumInstanceCount: 1", StringSplitOptions.None).Length - 1);
        Assert.Contains("Microsoft.Storage/storageAccounts/managementPolicies", environment, StringComparison.Ordinal);
        Assert.Contains("fp-source-incoming/uploads/", environment, StringComparison.Ordinal);
        Assert.Contains("daysAfterModificationGreaterThan: 1", environment, StringComparison.Ordinal);
        Assert.Contains("daysAfterCreationGreaterThan: 14", environment, StringComparison.Ordinal);
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
        Assert.Contains("siteConfig: {", functions, StringComparison.Ordinal);
        Assert.Contains("var additionalAppSettings = [for setting in items(appSettings)", functions, StringComparison.Ordinal);
        Assert.Contains("appSettings: concat(additionalAppSettings", functions, StringComparison.Ordinal);
        Assert.Contains("runtime: { name: 'dotnet-isolated', version: runtimeVersion }", functions, StringComparison.Ordinal);
        Assert.DoesNotContain("FUNCTIONS_WORKER_RUNTIME", functions + environment, StringComparison.Ordinal);
        Assert.DoesNotContain("resource settings 'config'", functions, StringComparison.Ordinal);
        Assert.Contains("module hostRbac './flex-function-rbac.bicep'", functions, StringComparison.Ordinal);
        Assert.Contains("name: '${appName}-host-rbac'", functions, StringComparison.Ordinal);
        Assert.Contains("hostBlobOwner", functionRbac, StringComparison.Ordinal);
        Assert.Contains("module environmentRbac './environment-rbac.bicep'", environment, StringComparison.Ordinal);
        Assert.Contains("generalWorkerHostIdentityPrincipalId: deployCompute ? generalWorker!.outputs.hostIdentityPrincipalId : ''", environment, StringComparison.Ordinal);
        Assert.Contains("resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing", environmentRbac, StringComparison.Ordinal);
        Assert.Contains("resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployCompute)", environmentRbac, StringComparison.Ordinal);
        Assert.DoesNotContain("apiContainer", environmentRbac, StringComparison.Ordinal);
        Assert.Contains("allowSharedKeyAccess: false", environment, StringComparison.Ordinal);
        Assert.Contains("allowSharedKeyAccess: false", functions, StringComparison.Ordinal);
        Assert.Contains("guid(vault.id, apiIdentityPrincipalId", environmentRbac, StringComparison.Ordinal);
        Assert.Contains("guid(hostStorage.id, hostIdentityPrincipalId", functionRbac, StringComparison.Ordinal);
        Assert.Contains("guid(documents.id, generalWorkerHostIdentityPrincipalId", environmentRbac, StringComparison.Ordinal);
        Assert.DoesNotContain("name: guid(vault.id, apiIdentity.properties.principalId", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("name: guid(hostStorage.id, hostIdentity.properties.principalId", functions, StringComparison.Ordinal);
        Assert.Contains("Storage Queue Data Message Sender", Read("docs", "AZURE-MVP-DEPLOYMENT.md"), StringComparison.Ordinal);
        Assert.DoesNotContain("listKeys(", main + environment + environmentRbac + containerApi + functions + functionRbac, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("AccountKey", main + environment + environmentRbac + containerApi + functions + functionRbac, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Dangerous_integrations_ship_disabled_and_secrets_are_not_parameters()
    {
        var environment = Read("infra", "modules", "environment.bicep");
        var example = Read("infra", "dev.parameters.example.json");
        foreach (var setting in new[]
        {
            "DefenderEventGrid__Enabled",
            "OfficialRss__Enabled",
            "Semantic__Enabled",
            "OpenAI__Enabled",
            "Alerts__Enabled",
            "Email__Enabled",
            "Billing__Enabled"
        })
            Assert.Contains($"{setting}: 'false'", environment, StringComparison.Ordinal);
        Assert.Contains("Authentication__Jwt__Issuer", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("JWT_ISSUER:", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("accessToken", example, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("clientSecret", example, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("password", example, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Deployment_is_manual_oidc_preflighted_and_apply_requires_confirmation()
    {
        var workflow = Read(".github", "workflows", "infra-dev.yml");
        var validation = Read(".github", "workflows", "infra-validate.yml");
        var ci = Read(".github", "workflows", "ci.yml");
        var script = Read("infra", "scripts", "deploy-dev.sh");
        var main = Read("infra", "main.bicep");
        var environment = Read("infra", "modules", "environment.bicep");
        var suffixGuardedScripts = new[]
        {
            script,
            Read("infra", "scripts", "prepare-key-vault-dev.sh"),
            Read("infra", "scripts", "prepare-database-dev.sh"),
            Read("infra", "scripts", "scale-api-dev.sh"),
            Read("infra", "scripts", "set-api-access-dev.sh"),
            Read("infra", "scripts", "rollback-api-dev.sh"),
            Read("infra", "scripts", "verify-dev.sh")
        };
        Assert.Contains("workflow_dispatch", workflow, StringComparison.Ordinal);
        Assert.Contains("id-token: write", workflow, StringComparison.Ordinal);
        Assert.Contains("azure/login@7184910d9eb2b1c5e48f7073824a90609bb9b6d6", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("actions/checkout@v", workflow + validation + ci, StringComparison.Ordinal);
        Assert.DoesNotContain("azure/login@v", workflow, StringComparison.Ordinal);
        Assert.Contains("package-ecosystem: github-actions", Read(".github", "dependabot.yml"), StringComparison.Ordinal);
        Assert.DoesNotContain("push:", workflow, StringComparison.Ordinal);
        Assert.Contains("confirmation:\n        description: Select the phrase", workflow, StringComparison.Ordinal);
        Assert.Contains("- NO-CONFIRMATION", workflow, StringComparison.Ordinal);
        Assert.Contains("- DEPLOY-DEV-BASE", workflow, StringComparison.Ordinal);
        Assert.Contains("DEPLOY-DEV", workflow, StringComparison.Ordinal);
        Assert.Contains("list-flexconsumption-runtimes", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_SQL_LOCATION", workflow + script, StringComparison.Ordinal);
        Assert.Contains("az sql db list-editions", script, StringComparison.Ordinal);
        Assert.Contains("sqlLocation", main + environment, StringComparison.Ordinal);
        Assert.Contains("'sql-${prefix}-${sqlLocation}'", environment, StringComparison.Ordinal);
        Assert.DoesNotContain("enablePurgeProtection: false", environment, StringComparison.Ordinal);
        Assert.Contains("sku.functionAppConfigProperties.runtime.version=='10.0'", script, StringComparison.Ordinal);
        Assert.Contains("dotnet10_runtime_count", script, StringComparison.Ordinal);
        Assert.DoesNotContain("grep -q '10.0'", script, StringComparison.Ordinal);
        Assert.Contains("Microsoft.App", script, StringComparison.Ordinal);
        Assert.Contains("az acr build", script, StringComparison.Ordinal);
        Assert.Contains("apply-base", script, StringComparison.Ordinal);
        Assert.Contains("DEPLOY-DEV-BASE", script, StringComparison.Ordinal);
        Assert.Contains("deployApiContainer=false", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_API_MIN_REPLICAS", script, StringComparison.Ordinal);
        Assert.Contains("deployment sub what-if", script, StringComparison.Ordinal);
        Assert.Contains("FullResourcePayloads", script, StringComparison.Ordinal);
        Assert.Contains("--no-pretty-print", script, StringComparison.Ordinal);
        Assert.Contains("redacted-budget-contact", script, StringComparison.Ordinal);
        Assert.Contains("redacted-sql-admin", script, StringComparison.Ordinal);
        Assert.Contains("AZURE_UNIQUE_SUFFIX is immutable", script, StringComparison.Ordinal);
        Assert.All(suffixGuardedScripts, guarded =>
            Assert.Contains("^[a-z0-9]{8}$", guarded, StringComparison.Ordinal));
        Assert.All(suffixGuardedScripts, guarded =>
            Assert.DoesNotContain("{4,8}", guarded, StringComparison.Ordinal));
        Assert.Contains("AZURE_APPLY_CONFIRMATION", script, StringComparison.Ordinal);
        Assert.Contains("github.ref != 'refs/heads/main'", workflow, StringComparison.Ordinal);
        Assert.Contains("inputs.expected_release_sha != github.sha", workflow, StringComparison.Ordinal);
        Assert.Contains("secrets.AZURE_BUDGET_EMAIL", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("vars.AZURE_BUDGET_EMAIL", workflow, StringComparison.Ordinal);
        Assert.Contains("scale-api", workflow, StringComparison.Ordinal);
        Assert.Contains("rollback-api", workflow, StringComparison.Ordinal);
        Assert.Contains("pause-api", workflow, StringComparison.Ordinal);
        Assert.Contains("resume-api", workflow, StringComparison.Ordinal);
        Assert.Contains("azcliversion: 2.88.0", workflow, StringComparison.Ordinal);
        Assert.Contains("azcliversion: 2.88.0", validation, StringComparison.Ordinal);
        Assert.DoesNotContain("azcliversion: 2.76.0", workflow + validation, StringComparison.Ordinal);
        Assert.Contains("workflow_dispatch", validation, StringComparison.Ordinal);
        Assert.Contains("default: '0'", workflow, StringComparison.Ordinal);
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
        Assert.Contains("apiAcrPull", Read("infra", "modules", "environment-rbac.bicep"), StringComparison.Ordinal);
        Assert.Contains("AZURE_CLIENT_ID: apiIdentity.properties.clientId", environment, StringComparison.Ordinal);
        Assert.Contains("AzureRuntimeCredentialFactory.Create", apiProgram, StringComparison.Ordinal);
        Assert.Contains("UserAssignedManagedIdentitySqlConnectionFactory", apiProgram, StringComparison.Ordinal);
    }

    [Fact]
    public void Frontend_deployment_is_manual_prebuilt_pinned_and_post_verified()
    {
        var workflow = Read(".github", "workflows", "frontend-dev.yml");
        var verifier = Read("infra", "scripts", "verify-dev.sh");
        var staticWebAppConfig = Read("frontend", "funding-platform-web", "public", "staticwebapp.config.json");

        Assert.Contains("workflow_dispatch:", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("\n  push:", workflow, StringComparison.Ordinal);
        Assert.Contains("github.ref != 'refs/heads/main'", workflow, StringComparison.Ordinal);
        Assert.Contains("EXPECTED_RELEASE_SHA", workflow, StringComparison.Ordinal);
        Assert.Contains("test \"$EXPECTED_RELEASE_SHA\" = \"$GITHUB_SHA\"", workflow, StringComparison.Ordinal);
        Assert.Contains("DEPLOY-DEV-FRONTEND", workflow, StringComparison.Ordinal);
        Assert.Contains("environment: dev", workflow, StringComparison.Ordinal);
        Assert.Equal(2, workflow.Split("id-token: write", StringSplitOptions.None).Length - 1);
        Assert.Contains("Build and test without Azure credentials", workflow, StringComparison.Ordinal);
        Assert.Contains("npm ci", workflow, StringComparison.Ordinal);
        Assert.Contains("npm run lint", workflow, StringComparison.Ordinal);
        Assert.Contains("npm test", workflow, StringComparison.Ordinal);
        Assert.Contains("VITE_API_BASE_URL", workflow, StringComparison.Ordinal);
        Assert.Contains("VITE_EXTERNAL_AUTH_BASE_URL", workflow, StringComparison.Ordinal);
        Assert.Contains("deploy-meta.json", workflow, StringComparison.Ordinal);
        Assert.Contains("az staticwebapp secrets list", workflow, StringComparison.Ordinal);
        Assert.Contains("::add-mask::", workflow, StringComparison.Ordinal);
        Assert.Contains("Azure/static-web-apps-deploy@4d27395796ac319302594769cfe812bd207490b1", workflow, StringComparison.Ordinal);
        Assert.Contains("app_location: frontend-dist", workflow, StringComparison.Ordinal);
        Assert.Contains("output_location: ''", workflow, StringComparison.Ordinal);
        Assert.Contains("skip_app_build: true", workflow, StringComparison.Ordinal);
        Assert.Contains("skip_api_build: true", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("repo_token:", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("publish-profile", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("az staticwebapp show", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("az staticwebapp show", verifier, StringComparison.Ordinal);
        Assert.Contains("--resource-type Microsoft.Web/staticSites", workflow, StringComparison.Ordinal);
        Assert.Contains("--resource-type Microsoft.Web/staticSites", verifier, StringComparison.Ordinal);
        Assert.Contains("properties.deploymentAuthPolicy", workflow, StringComparison.Ordinal);
        Assert.Contains("properties.deploymentAuthPolicy", verifier, StringComparison.Ordinal);
        Assert.Contains("verify-dev.sh frontend", workflow, StringComparison.Ordinal);
        Assert.Contains("stage must be base, api or frontend", verifier, StringComparison.Ordinal);
        Assert.Contains("EXPECTED_FRONTEND_RELEASE_SHA", verifier, StringComparison.Ordinal);
        Assert.Contains("deploy-meta.json", verifier, StringComparison.Ordinal);
        Assert.Contains("Access-Control-Allow-Origin", verifier, StringComparison.Ordinal);
        Assert.Contains("Access-Control-Request-Method", verifier, StringComparison.Ordinal);
        Assert.DoesNotContain("awk", verifier, StringComparison.Ordinal);
        Assert.DoesNotContain("| tr ", verifier, StringComparison.Ordinal);
        Assert.Contains("while IFS= read -r line", verifier, StringComparison.Ordinal);
        Assert.Contains("authorization,content-type", verifier, StringComparison.Ordinal);
        Assert.Contains("X-Frame-Options", verifier, StringComparison.Ordinal);
        Assert.Contains("\"rewrite\": \"/index.html\"", staticWebAppConfig, StringComparison.Ordinal);
    }

    [Fact]
    public void Worker_delivery_is_offline_reproducible_and_rejects_local_configuration()
    {
        var workflow = Read(".github", "workflows", "ci.yml");
        var packager = Read("infra", "scripts", "package-workers.py");
        var generalProject = Read(
            "src", "FundingPlatform.Workers", "FundingPlatform.Workers.csproj");
        var extractionProject = Read(
            "src", "FundingPlatform.ExtractionWorkers",
            "FundingPlatform.ExtractionWorkers.csproj");

        Assert.Contains("package-workers.py build", workflow, StringComparison.Ordinal);
        Assert.Contains("package-workers.py verify", workflow, StringComparison.Ordinal);
        Assert.Contains("worker-packages-${{ github.sha }}", workflow, StringComparison.Ordinal);
        Assert.Contains("actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
            workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("azure/login", workflow, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("zipfile.ZIP_STORED", packager, StringComparison.Ordinal);
        Assert.Contains("FIXED_ZIP_TIMESTAMP", packager, StringComparison.Ordinal);
        Assert.Contains("SHA256SUMS", packager, StringComparison.Ordinal);
        Assert.Contains("functions.metadata", packager, StringComparison.Ordinal);
        Assert.Contains("local.settings.json", packager, StringComparison.Ordinal);
        Assert.Contains("--no-restore", packager, StringComparison.Ordinal);
        Assert.Contains("UseAppHost=false", packager, StringComparison.Ordinal);
        Assert.All(new[] { generalProject, extractionProject }, project =>
        {
            Assert.Contains("<None Update=\"local.settings.json\">", project,
                StringComparison.Ordinal);
            Assert.Contains("<CopyToPublishDirectory>Never</CopyToPublishDirectory>", project,
                StringComparison.Ordinal);
        });
    }

    [Fact]
    public void Post_deploy_verifier_is_read_only_digest_aware_and_cost_bounded()
    {
        var verifier = Read("infra", "scripts", "verify-dev.sh");
        var checklist = Read("infra", "DEV-DEPLOYMENT-CHECKLIST.md");
        var databasePreparation = Read("infra", "scripts", "prepare-database-dev.sh");
        var keyVaultPreparation = Read("infra", "scripts", "prepare-key-vault-dev.sh");

        Assert.Contains("stage must be base, api or frontend", verifier, StringComparison.Ordinal);
        Assert.Contains("GP_S_Gen5_1|1|60|0.5", verifier, StringComparison.Ordinal);
        Assert.Contains("7|12", verifier, StringComparison.Ordinal);
        Assert.Contains("maximumInstanceCount", verifier, StringComparison.Ordinal);
        Assert.Contains("${registry_server}/rise-funding-api@", verifier, StringComparison.Ordinal);
        Assert.Contains("^sha256:[0-9a-f]{64}$", verifier, StringComparison.Ordinal);
        Assert.Contains("/health", verifier, StringComparison.Ordinal);
        Assert.DoesNotContain("/health/ready", verifier, StringComparison.Ordinal);
        Assert.Contains("/api/v1/funding-opportunities/", verifier, StringComparison.Ordinal);
        Assert.Contains("app.Environment.IsDevelopment()", Read("src", "FundingPlatform.Api", "Program.cs"), StringComparison.Ordinal);
        Assert.Contains("AZURE_SUBSCRIPTION_ID", verifier, StringComparison.Ordinal);
        Assert.Contains("AZURE_TENANT_ID", verifier, StringComparison.Ordinal);
        Assert.Contains("AZURE_SQL_LOCATION", verifier, StringComparison.Ordinal);
        Assert.Contains("sql server show", verifier, StringComparison.Ordinal);
        Assert.Contains("--retry-max-time 120", verifier, StringComparison.Ordinal);
        Assert.DoesNotContain("secret list", verifier, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("group delete", verifier, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("containerapp update", verifier, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("DEPLOY-DEV-BASE", checklist, StringComparison.Ordinal);
        Assert.Contains("exactamente 8 caracteres `[a-z0-9]`", checklist, StringComparison.Ordinal);
        Assert.Contains("conservar exactamente el mismo", checklist, StringComparison.Ordinal);
        Assert.Contains("No cambiar el sufijo ni borrar recursos", checklist, StringComparison.Ordinal);
        Assert.Contains("No publicar todavía Functions", checklist, StringComparison.Ordinal);
        Assert.Contains("bash infra/scripts/prepare-key-vault-dev.sh", checklist, StringComparison.Ordinal);
        Assert.Contains("bash infra/scripts/prepare-database-dev.sh", checklist, StringComparison.Ordinal);
        Assert.Contains("--query '[0].sid'", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("--query '[0].login'", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("--query '[0].tenantId'", databasePreparation, StringComparison.Ordinal);
        Assert.DoesNotContain("[0].[sid, login, tenantId]", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("get-access-token", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("https://database.windows.net/", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("AZURE_TOKEN_CREDENTIALS=AzureCliCredential", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("expected_release_sha=$RF_DEV_RELEASE_SHA", checklist, StringComparison.Ordinal);
        Assert.Contains("RF_DEV_DEPLOYER_CLIENT_ID", checklist, StringComparison.Ordinal);
        Assert.Contains("RF_DEV_SUBSCRIPTION_ID", checklist, StringComparison.Ordinal);
        Assert.Contains("RF_DEV_TENANT_ID", checklist, StringComparison.Ordinal);
        Assert.Contains("az account show --query tenantId", checklist, StringComparison.Ordinal);
        Assert.DoesNotContain("FROM EXTERNAL PROVIDER", checklist, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("repo:Algaete@51843665/riseFundingOrg@1344044015:environment:dev", checklist, StringComparison.Ordinal);
        Assert.Contains("pause-api", checklist, StringComparison.Ordinal);
        Assert.Contains("Todo `apply` vuelve", checklist, StringComparison.Ordinal);
        var scale = Read("infra", "scripts", "scale-api-dev.sh");
        var rollback = Read("infra", "scripts", "rollback-api-dev.sh");
        var access = Read("infra", "scripts", "set-api-access-dev.sh");
        Assert.Contains("SCALE-DEV-API", scale, StringComparison.Ordinal);
        Assert.Contains("properties.template.scale.maxReplicas=1", scale, StringComparison.Ordinal);
        Assert.DoesNotContain("az containerapp", scale + verifier, StringComparison.Ordinal);
        Assert.DoesNotContain("acr build", scale, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("ROLLBACK-DEV-API", rollback, StringComparison.Ordinal);
        Assert.Contains("rise-funding-api@", rollback, StringComparison.Ordinal);
        Assert.Contains("latestReadyRevisionName", rollback, StringComparison.Ordinal);
        Assert.Contains("verify-dev.sh api", rollback, StringComparison.Ordinal);
        Assert.DoesNotContain("acr build", rollback, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("PAUSE-DEV-API", access, StringComparison.Ordinal);
        Assert.Contains("RESUME-DEV-API", access, StringComparison.Ordinal);
        Assert.Contains("properties.configuration.ingress.external", access, StringComparison.Ordinal);
        Assert.Contains("properties.template.scale.minReplicas=\"$desired_min\"", access, StringComparison.Ordinal);
        Assert.DoesNotContain("acr build", access, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("git status --porcelain", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("MIGRATION_EXPECTED_DATABASE_NAME=risefunding-dev", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("MIGRATION_EXPECTED_SERVER_FQDN", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("Expected exactly one SQL server", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("id-rf-dev-${AZURE_UNIQUE_SUFFIX}-api", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("trap cleanup_sql_firewall EXIT", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("DOTNET_ENVIRONMENT=Staging", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("\"${migrator[@]}\" --preflight", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("--provision-runtime-identities", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("--verify-runtime-identities", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("Full-Text 8A: listo", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("Migraciones registradas: 29", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("Migraciones locales: 29", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("bootstrap-superadmin", databasePreparation, StringComparison.Ordinal);
        Assert.Contains("refusing to overwrite", keyVaultPreparation, StringComparison.Ordinal);
        Assert.Contains("openssl rand 64", keyVaultPreparation, StringComparison.Ordinal);
        Assert.Contains("--file", keyVaultPreparation, StringComparison.Ordinal);
        Assert.Contains("temporary_assignment_id", keyVaultPreparation, StringComparison.Ordinal);
        Assert.Contains("role assignment delete --ids", keyVaultPreparation, StringComparison.Ordinal);
        Assert.DoesNotContain("secret show", keyVaultPreparation, StringComparison.OrdinalIgnoreCase);
    }

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
