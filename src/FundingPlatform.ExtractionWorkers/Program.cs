using System.Diagnostics;
using Azure.Core;
using Azure.Monitor.OpenTelemetry.Exporter;
using Azure.Storage.Blobs;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.ExtractionWorkers.Extraction;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.Infrastructure.Observability;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using FundingPlatform.Infrastructure.SourceDocuments.Extraction;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Azure.Functions.Worker.OpenTelemetry;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Trace;
using Serilog;

LocalEnvironmentLoader.TryLoad();
Activity.DefaultIdFormat = ActivityIdFormat.W3C;
Activity.ForceDefaultIdFormat = true;

var builder = FunctionsApplication.CreateBuilder(args);
builder.Configuration.AddFundingPlatformAliases();

var applicationInsightsConnectionString =
    builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]?.Trim();
var hasApplicationInsightsClientId = Guid.TryParse(
    builder.Configuration["APPLICATIONINSIGHTS_CLIENT_ID"],
    out var applicationInsightsClientId);
if (!builder.Environment.IsDevelopment() &&
    (string.IsNullOrWhiteSpace(applicationInsightsConnectionString) ||
     !hasApplicationInsightsClientId))
{
    throw new InvalidOperationException(
        "Application Insights must use an explicit worker-host managed identity outside development.");
}

if (!string.IsNullOrWhiteSpace(applicationInsightsConnectionString))
{
    RequireQueryStringRedaction(builder.Configuration);
    var telemetryCredential = AzureRuntimeCredentialFactory.Create(
        hasApplicationInsightsClientId ? applicationInsightsClientId : null,
        builder.Environment.EnvironmentName);
    builder.Services.AddOpenTelemetry()
        .WithTracing(tracing => tracing.AddProcessor<TelemetryPrivacyProcessor>())
        .WithLogging(logging => logging.AddProcessor<TelemetryLogPrivacyProcessor>())
        .UseFunctionsWorkerDefaults()
        .UseAzureMonitorExporter(options =>
        {
            options.ConnectionString = applicationInsightsConnectionString;
            options.Credential = telemetryCredential;
            options.EnableLiveMetrics = false;
            options.TracesPerSecond = 1.0;
        });
    builder.Services.PostConfigure<OpenTelemetryLoggerOptions>(options =>
    {
        options.IncludeScopes = false;
        options.IncludeFormattedMessage = false;
    });
}

builder.Services.AddSerilog((_, loggerConfiguration) =>
    loggerConfiguration
        .MinimumLevel.Information()
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "FundingPlatform.ExtractionWorkers"),
    preserveStaticLogger: false,
    writeToProviders: true);

builder.Services.AddOptions<SourceDocumentExtractionOptions>()
    .Bind(builder.Configuration.GetSection(SourceDocumentExtractionOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<SourceDocumentExtractionOptions>,
    SourceDocumentExtractionOptionsValidator>();

var hostStorage = ImportQueueStorageConfiguration.Resolve(builder.Configuration);
var documentQueueStorage =
    DocumentExtractionQueueStorageConfiguration.Resolve(builder.Configuration);
var extractionManagedIdentityClientId =
    DocumentExtractionQueueStorageConfiguration.RequireExtractionManagedIdentity(
        documentQueueStorage, builder.Environment.EnvironmentName);
var blobServiceUri = ReadBlobServiceUri(builder.Configuration["SourceDocuments:BlobServiceUri"]);
DocumentExtractionQueueStorageConfiguration.EnsureHostStorageIsolatedFromDocumentBlobs(
    hostStorage, blobServiceUri, builder.Environment.EnvironmentName);
var trustedContainer = builder.Configuration["SourceDocuments:TrustedContainer"]?.Trim();
if (string.IsNullOrWhiteSpace(trustedContainer))
{
    throw new InvalidOperationException(
        "SourceDocuments:TrustedContainer is required by the isolated extraction worker.");
}

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<TokenCredential>(
    AzureRuntimeCredentialFactory.Create(
        extractionManagedIdentityClientId,
        builder.Environment.EnvironmentName));
builder.Services.AddSingleton(serviceProvider => new BlobServiceClient(
    blobServiceUri,
    serviceProvider.GetRequiredService<TokenCredential>()));
builder.Services.AddSingleton<ISourceDocumentExtractionBlobReader>(serviceProvider =>
    new AzureTrustedSourceDocumentReader(
        serviceProvider.GetRequiredService<BlobServiceClient>(),
        trustedContainer));
builder.Services.AddSingleton<ISourceDocumentTextExtractor, SecurePdfTextExtractor>();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<SourceDocumentExtractionOptions>>()
        .Value.ToPolicy());
// Construct the factory now instead of deferring it to the first queue message:
// a hosted worker with an ambiguous/unsafe SQL identity must fail at startup.
ISqlConnectionFactory sqlConnectionFactory =
    extractionManagedIdentityClientId.HasValue
        ? new UserAssignedManagedIdentitySqlConnectionFactory(
            builder.Configuration,
            extractionManagedIdentityClientId.Value)
        // Local development intentionally keeps Azure CLI / developer
        // credentials through Active Directory Default.
        : new SqlConnectionFactory(builder.Configuration);
builder.Services.AddSingleton(sqlConnectionFactory);
builder.Services.AddScoped<ISourceDocumentExtractionRepository,
    SqlSourceDocumentExtractionRepository>();
builder.Services.AddScoped<SourceDocumentExtractionProcessingService>();
builder.Services.AddScoped<SourceDocumentExtractionWatchdogService>();

builder.Build().Run();

static Uri ReadBlobServiceUri(string? value)
{
    if (!Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) ||
        uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
        uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.UserInfo) ||
        !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment) ||
        !uri.Host.EndsWith(".blob.core.windows.net", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(
            "SourceDocuments:BlobServiceUri must be a credential-free Azure Blob HTTPS endpoint.");
    }

    return uri;
}

static void RequireQueryStringRedaction(IConfiguration configuration)
{
    foreach (var setting in new[]
    {
        "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION",
        "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION"
    })
    {
        if (!string.Equals(configuration[setting], "false", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"{setting} must be false so query-string secrets cannot enter telemetry.");
        }
    }
}
