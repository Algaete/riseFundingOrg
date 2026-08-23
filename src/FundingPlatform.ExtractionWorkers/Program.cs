using Azure.Core;
using Azure.Storage.Blobs;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.ExtractionWorkers.Extraction;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using FundingPlatform.Infrastructure.SourceDocuments.Extraction;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Serilog;

LocalEnvironmentLoader.TryLoad();

var builder = FunctionsApplication.CreateBuilder(args);
builder.Configuration.AddFundingPlatformAliases();

builder.Services.AddSerilog((_, loggerConfiguration) =>
    loggerConfiguration
        .MinimumLevel.Information()
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "FundingPlatform.ExtractionWorkers")
        .WriteTo.Console());

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
