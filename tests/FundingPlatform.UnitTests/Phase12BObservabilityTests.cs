using FundingPlatform.Infrastructure.Persistence.Migrations;

namespace FundingPlatform.UnitTests;

public sealed class Phase12BObservabilityTests
{
    [Fact]
    public void Azure_monitor_is_identity_only_cost_bounded_and_privacy_preserving()
    {
        var packages = Read("Directory.Packages.props");
        var apiProject = Read("src", "FundingPlatform.Api", "FundingPlatform.Api.csproj");
        var apiProgram = Read("src", "FundingPlatform.Api", "Program.cs");
        var environment = Read("infra", "modules", "environment.bicep");
        var functionModule = Read("infra", "modules", "flex-function.bicep");
        var environmentRbac = Read("infra", "modules", "environment-rbac.bicep");
        var functionRbac = Read("infra", "modules", "flex-function-rbac.bicep");
        var runbook = Read("docs", "runbooks", "observability.md");

        Assert.Contains(
            "Azure.Monitor.OpenTelemetry.AspNetCore\" Version=\"1.6.0\"",
            packages,
            StringComparison.Ordinal);
        Assert.Contains(
            "Azure.Monitor.OpenTelemetry.AspNetCore",
            apiProject,
            StringComparison.Ordinal);
        Assert.Contains(".UseAzureMonitor(options =>", apiProgram, StringComparison.Ordinal);
        Assert.Contains("AddProcessor<TelemetryPrivacyProcessor>()", apiProgram,
            StringComparison.Ordinal);
        Assert.Contains("AddProcessor<TelemetryLogPrivacyProcessor>()", apiProgram,
            StringComparison.Ordinal);
        Assert.Contains("options.IncludeScopes = false", apiProgram, StringComparison.Ordinal);
        Assert.Contains("options.Credential = azureCredential", apiProgram, StringComparison.Ordinal);
        Assert.Contains("options.EnableLiveMetrics = false", apiProgram, StringComparison.Ordinal);
        Assert.Contains("options.TracesPerSecond = 1.0", apiProgram, StringComparison.Ordinal);
        Assert.Contains("options.RecordException = false", apiProgram, StringComparison.Ordinal);
        Assert.Contains("StartsWithSegments(\"/health\")", apiProgram, StringComparison.Ordinal);
        Assert.Contains("Activity.DefaultIdFormat = ActivityIdFormat.W3C", apiProgram,
            StringComparison.Ordinal);
        Assert.Contains("Activity.Current?.TraceId.ToString()", apiProgram, StringComparison.Ordinal);
        Assert.Contains("new JsonFormatter()", apiProgram, StringComparison.Ordinal);
        Assert.Contains("builder.Logging.ClearProviders()", apiProgram, StringComparison.Ordinal);
        Assert.Contains("writeToProviders: true", apiProgram, StringComparison.Ordinal);

        Assert.Contains("DisableLocalAuth: true", environment, StringComparison.Ordinal);
        Assert.Contains("APPLICATIONINSIGHTS_CLIENT_ID", functionModule, StringComparison.Ordinal);
        Assert.Contains("hostIdentity.properties.clientId", functionModule, StringComparison.Ordinal);
        Assert.Contains("hostMetricsPublisher", functionRbac, StringComparison.Ordinal);
        Assert.Contains("resource apiMetrics ", environmentRbac, StringComparison.Ordinal);
        Assert.Contains("No capturar cuerpos, cookies, encabezados de autorización", runbook,
            StringComparison.Ordinal);
        Assert.Contains("objetivo de `1.0` traza por segundo", runbook, StringComparison.Ordinal);
        Assert.Contains("No publicar Functions", runbook, StringComparison.Ordinal);
        Assert.Contains("name: 'OTEL_TRACES_SAMPLER', value: 'microsoft.rate_limited'",
            functionModule, StringComparison.Ordinal);
        Assert.Contains("name: 'OTEL_TRACES_SAMPLER_ARG', value: '1.0'",
            functionModule, StringComparison.Ordinal);

        foreach (var setting in QueryStringRedactionSettings)
        {
            Assert.Contains($"{setting}: 'false'", environment, StringComparison.Ordinal);
            Assert.Contains($"name: '{setting}', value: 'false'", functionModule,
                StringComparison.Ordinal);
            Assert.Contains(setting, apiProgram, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void Function_workers_emit_open_telemetry_through_their_host_identity()
    {
        var packages = Read("Directory.Packages.props");
        Assert.Contains(
            "Azure.Monitor.OpenTelemetry.Exporter\" Version=\"1.9.0\"",
            packages,
            StringComparison.Ordinal);
        Assert.Contains(
            "Microsoft.Azure.Functions.Worker.OpenTelemetry\" Version=\"1.2.0\"",
            packages,
            StringComparison.Ordinal);

        foreach (var projectName in new[]
                 {
                     "FundingPlatform.Workers",
                     "FundingPlatform.ExtractionWorkers"
                 })
        {
            var project = Read("src", projectName, $"{projectName}.csproj");
            var program = Read("src", projectName, "Program.cs");
            var host = Read("src", projectName, "host.json");

            Assert.Contains("Azure.Monitor.OpenTelemetry.Exporter", project,
                StringComparison.Ordinal);
            Assert.Contains("Microsoft.Azure.Functions.Worker.OpenTelemetry", project,
                StringComparison.Ordinal);
            Assert.Contains("\"telemetryMode\": \"OpenTelemetry\"", host,
                StringComparison.Ordinal);
            Assert.Contains("UseFunctionsWorkerDefaults()", program, StringComparison.Ordinal);
            Assert.Contains("UseAzureMonitorExporter", program, StringComparison.Ordinal);
            Assert.Contains("AddProcessor<TelemetryPrivacyProcessor>()", program,
                StringComparison.Ordinal);
            Assert.Contains("AddProcessor<TelemetryLogPrivacyProcessor>()", program,
                StringComparison.Ordinal);
            Assert.Contains("options.IncludeScopes = false", program, StringComparison.Ordinal);
            Assert.Contains("APPLICATIONINSIGHTS_CLIENT_ID", program, StringComparison.Ordinal);
            Assert.Contains("options.Credential = telemetryCredential", program,
                StringComparison.Ordinal);
            Assert.Contains("options.EnableLiveMetrics = false", program, StringComparison.Ordinal);
            Assert.Contains("options.TracesPerSecond = 1.0", program, StringComparison.Ordinal);
            Assert.Contains("Activity.DefaultIdFormat = ActivityIdFormat.W3C", program,
                StringComparison.Ordinal);
            Assert.DoesNotContain("AddJsonConsole", program, StringComparison.Ordinal);
            Assert.Contains("writeToProviders: true", program, StringComparison.Ordinal);
            foreach (var setting in QueryStringRedactionSettings)
                Assert.Contains(setting, program, StringComparison.Ordinal);
        }
    }

    private static readonly string[] QueryStringRedactionSettings =
    [
        "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION",
        "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION"
    ];

    private static string Read(params string[] parts)
    {
        var root = SolutionRootLocator.Find(AppContext.BaseDirectory);
        return File.ReadAllText(Path.Combine([root, .. parts]));
    }
}
