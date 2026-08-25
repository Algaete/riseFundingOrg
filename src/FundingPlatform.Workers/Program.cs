using System.Net;
using Azure.Core;
using Azure.Storage.Blobs;
using Azure.Storage.Queues;
using Azure.Storage.Queues.Models;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Imports;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.FundingSources;
using FundingPlatform.Infrastructure.FundingSources.GrantsGov;
using FundingPlatform.Infrastructure.FundingSources.Rss;
using FundingPlatform.Infrastructure.Persistence.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Imports;
using FundingPlatform.Infrastructure.Persistence.Semantics;
using FundingPlatform.Infrastructure.Persistence.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using FundingPlatform.Infrastructure.SourceDocuments.Storage;
using FundingPlatform.Infrastructure.Semantics;
using FundingPlatform.Workers.Configuration;
using FundingPlatform.Workers.Security;
using FundingPlatform.Workers.Queue;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
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
        .Enrich.WithProperty("Application", "FundingPlatform.Workers")
        .WriteTo.Console());

builder.Services.AddOptions<ImportWorkerOptions>()
    .Bind(builder.Configuration.GetSection(ImportWorkerOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<ImportWorkerOptions>, ImportWorkerOptionsValidator>();
builder.Services.AddOptions<SourceDocumentOptions>()
    .Bind(builder.Configuration.GetSection(SourceDocumentOptions.SectionName))
    .Validate(
        options => SourceDocumentOptions.IsValid(options, builder.Environment.EnvironmentName),
        "SourceDocuments configuration is invalid.")
    .ValidateOnStart();
builder.Services.AddOptions<DefenderEventGridOptions>()
    .Bind(builder.Configuration.GetSection(DefenderEventGridOptions.SectionName))
    .Validate(
        options => DefenderEventGridOptions.IsValid(
            options,
            builder.Environment.EnvironmentName,
            builder.Configuration["SourceDocuments:BlobServiceUri"]),
        "DefenderEventGrid configuration must be complete outside local development.")
    .ValidateOnStart();
builder.Services.AddOptions<OfficialRssOptions>()
    .Bind(builder.Configuration.GetSection(OfficialRssOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<OfficialRssOptions>, OfficialRssOptionsValidator>();
builder.Services.AddOptions<ContentRetentionOptions>()
    .Bind(builder.Configuration.GetSection(ContentRetentionOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<ContentRetentionOptions>,
    ContentRetentionOptionsValidator>();
builder.Services.AddOptions<SemanticOptions>()
    .Bind(builder.Configuration.GetSection(SemanticOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<SemanticOptions>,
    SemanticWorkerOptionsValidator>();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<SemanticOptions>>().Value.ToPolicy());

var queueStorage = ImportQueueStorageConfiguration.Resolve(builder.Configuration);
var documentExtractionQueueStorage =
    DocumentExtractionQueueStorageConfiguration.Resolve(builder.Configuration);
var documentExtractionQueueSenderIdentity =
    DocumentExtractionQueueStorageConfiguration.RequireSenderManagedIdentity(
        documentExtractionQueueStorage, builder.Environment.EnvironmentName);
builder.Services.AddSingleton(queueStorage);
builder.Services.AddSingleton(documentExtractionQueueStorage);

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<GovernedAcquisitionRequestGate>();
builder.Services.AddSingleton(ImportWorkerIdentity.Create());
builder.Services.AddSingleton(SemanticWorkerIdentity.Create());
builder.Services.AddSingleton<TokenCredential>(
    AzureRuntimeCredentialFactory.Create(
        queueStorage.ManagedIdentityClientId,
        builder.Environment.EnvironmentName));
ISqlConnectionFactory sqlConnectionFactory = builder.Environment.IsDevelopment()
    ? new SqlConnectionFactory(builder.Configuration)
    : new UserAssignedManagedIdentitySqlConnectionFactory(
        builder.Configuration,
        queueStorage.ManagedIdentityClientId!.Value);
builder.Services.AddSingleton(sqlConnectionFactory);
builder.Services.AddScoped<IFundingOpportunityRepository, SqlFundingOpportunityRepository>();
builder.Services.AddScoped<IImportRunRepository, SqlImportRunRepository>();
builder.Services.AddScoped<IFundingSourceAcquisitionAuthorizer,
    SqlFundingSourceAcquisitionAuthorizer>();
builder.Services.AddScoped<IImportOutboxRepository, SqlImportOutboxRepository>();
builder.Services.AddScoped<IContentRetentionRepository, SqlContentRetentionRepository>();
builder.Services.AddScoped<ISourceDocumentContentRetentionRepository,
    SqlSourceDocumentContentRetentionRepository>();
builder.Services.AddScoped<ISourceDocumentRepository, SqlSourceDocumentRepository>();
builder.Services.AddScoped<ISemanticProcessingRepository,
    SqlSemanticProcessingRepository>();
builder.Services.AddScoped<IDefenderScanReceiptRepository, SqlDefenderScanReceiptRepository>();
builder.Services.AddScoped<IDefenderScanWatchdogRepository,
    SqlDefenderScanWatchdogRepository>();
builder.Services.AddSingleton<AzureSourceDocumentBlobStore>();
builder.Services.AddSingleton<ISourceDocumentBlobStore>(serviceProvider =>
    serviceProvider.GetRequiredService<AzureSourceDocumentBlobStore>());
builder.Services.AddSingleton<ISourceDocumentRetentionBlobStore>(serviceProvider =>
    serviceProvider.GetRequiredService<AzureSourceDocumentBlobStore>());
builder.Services.AddSingleton(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<SourceDocumentOptions>>().Value;
    return new BlobServiceClient(
        new Uri(options.BlobServiceUri),
        serviceProvider.GetRequiredService<TokenCredential>());
});
builder.Services.AddSingleton(serviceProvider =>
{
    var defender = serviceProvider.GetRequiredService<IOptions<DefenderEventGridOptions>>().Value;
    var documents = serviceProvider.GetRequiredService<IOptions<SourceDocumentOptions>>().Value;
    return defender.ToPolicy(
        new Uri(documents.BlobServiceUri),
        documents.QuarantineContainer,
        documents.TrustedContainer,
        documents.MaxBytes);
});
builder.Services.AddSingleton<IEventGridBearerTokenValidator,
    EntraEventGridBearerTokenValidator>();
builder.Services.AddScoped<DefenderEventGridService>();
builder.Services.AddScoped<DefenderScanWatchdogService>();
builder.Services.AddScoped<ContentRetentionService>();
builder.Services.AddScoped<SourceDocumentContentRetentionService>();
builder.Services.AddSingleton<IEmbeddingService>(_ =>
    builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing")
        ? new DeterministicDevelopmentEmbeddingService()
        : new UnavailableEmbeddingService());
builder.Services.AddScoped(serviceProvider => new SemanticProcessingService(
    serviceProvider.GetRequiredService<ISemanticProcessingRepository>(),
    serviceProvider.GetRequiredService<IEmbeddingService>(),
    serviceProvider.GetRequiredService<SemanticProcessingPolicy>(),
    serviceProvider.GetRequiredService<TimeProvider>(),
    serviceProvider.GetRequiredService<SemanticWorkerIdentity>().InstanceId));

builder.Services.AddHttpClient<GrantsGovFundingSourceProvider>((serviceProvider, client) =>
    {
        var options = serviceProvider.GetRequiredService<IOptions<ImportWorkerOptions>>().Value;
        client.BaseAddress = new Uri(GrantsGovFundingSourceProvider.ApiBaseUrl);
        client.Timeout = TimeSpan.FromSeconds(options.GrantsGovTimeoutSeconds);
        client.DefaultRequestHeaders.UserAgent.ParseAdd("FundingPlatform-Workers/1.0");
    })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        AllowAutoRedirect = false,
        AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
        ConnectTimeout = TimeSpan.FromSeconds(10),
        MaxConnectionsPerServer = 2,
        PooledConnectionLifetime = TimeSpan.FromMinutes(10)
    });
builder.Services.AddScoped<IFundingSourceProvider>(serviceProvider =>
    serviceProvider.GetRequiredService<GrantsGovFundingSourceProvider>());
var configuredRss = builder.Configuration
    .GetSection(OfficialRssOptions.SectionName)
    .Get<OfficialRssOptions>() ?? new OfficialRssOptions();
if (configuredRss.Enabled)
{
    var fixedFeed = new Uri(configuredRss.FeedUri, UriKind.Absolute);
    builder.Services.AddHttpClient<OfficialRssFundingSourceProvider>((serviceProvider, client) =>
        {
            var options = serviceProvider.GetRequiredService<IOptions<OfficialRssOptions>>().Value;
            var feed = new Uri(options.FeedUri, UriKind.Absolute);
            client.BaseAddress = new Uri(feed.GetLeftPart(UriPartial.Authority));
            client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
        })
        .ConfigurePrimaryHttpMessageHandler(() =>
            PublicNetworkSocketsHttpHandler.Create(fixedFeed.Host));
    builder.Services.AddScoped<IFundingSourceProvider>(serviceProvider =>
        serviceProvider.GetRequiredService<OfficialRssFundingSourceProvider>());
}
builder.Services.AddScoped<IFundingSourceProviderRegistry>(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<ImportWorkerOptions>>().Value;
    var allowed = options.GetAllowedProviders();
    if (allowed.Contains(OfficialRssFundingSourceProvider.Code, StringComparer.Ordinal) &&
        !serviceProvider.GetRequiredService<IOptions<OfficialRssOptions>>().Value.Enabled)
    {
        throw new InvalidOperationException(
            "The official-rss provider is allowlisted but its governed configuration is disabled.");
    }
    return new FundingSourceProviderRegistry(
        serviceProvider.GetServices<IFundingSourceProvider>(),
        allowed);
});

builder.Services.AddSingleton(serviceProvider =>
{
    var storage = serviceProvider.GetRequiredService<ImportQueueStorageSettings>();
    var queueOptions = new QueueClientOptions { MessageEncoding = QueueMessageEncoding.Base64 };
    if (storage.UsesManagedIdentity)
    {
        var queueUri = new Uri(
            new Uri(storage.QueueServiceUri!.AbsoluteUri.TrimEnd('/') + "/"),
            "imports");
        return new QueueClient(
            queueUri,
            serviceProvider.GetRequiredService<TokenCredential>(),
            queueOptions);
    }

    return new QueueClient(
        storage.DevelopmentConnectionString, "imports", queueOptions);
});
builder.Services.AddSingleton<AzureImportQueuePublisher>();
builder.Services.AddSingleton<IImportQueuePublisher>(serviceProvider =>
    serviceProvider.GetRequiredService<AzureImportQueuePublisher>());
builder.Services.AddSingleton<IImportQueueProvisioningClient>(serviceProvider =>
    serviceProvider.GetRequiredService<AzureImportQueuePublisher>());
builder.Services.AddSingleton(serviceProvider => new ImportQueueProvisioningService(
    serviceProvider.GetRequiredService<IImportQueueProvisioningClient>(),
    createIfMissing: !queueStorage.UsesManagedIdentity));
builder.Services.AddHostedService<ImportQueueStartupService>();

builder.Services.AddSingleton<AzureSourceDocumentExtractionQueuePublisher>(serviceProvider =>
{
    var storage = serviceProvider.GetRequiredService<DocumentExtractionQueueStorageSettings>();
    var queueOptions = new QueueClientOptions { MessageEncoding = QueueMessageEncoding.Base64 };
    QueueClient queueClient;
    if (storage.UsesManagedIdentity)
    {
        var queueUri = new Uri(
            new Uri(storage.QueueServiceUri!.AbsoluteUri.TrimEnd('/') + "/"),
            "document-extractions");
        var credential = AzureRuntimeCredentialFactory.Create(
            documentExtractionQueueSenderIdentity,
            builder.Environment.EnvironmentName);
        queueClient = new QueueClient(
            queueUri,
            credential,
            queueOptions);
    }
    else
    {
        queueClient = new QueueClient(
            storage.DevelopmentConnectionString,
            "document-extractions",
            queueOptions);
    }
    return new AzureSourceDocumentExtractionQueuePublisher(queueClient);
});
builder.Services.AddSingleton<ISourceDocumentExtractionQueuePublisher>(serviceProvider =>
    serviceProvider.GetRequiredService<AzureSourceDocumentExtractionQueuePublisher>());
builder.Services.AddHostedService<SourceDocumentExtractionQueueStartupService>();

builder.Services.AddScoped<ImportRunService>();
builder.Services.AddScoped<IImportRunService>(serviceProvider =>
    serviceProvider.GetRequiredService<ImportRunService>());
builder.Services.AddScoped<ImportSchedulerService>();
builder.Services.AddScoped(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<ImportWorkerOptions>>().Value;
    return new ImportRunProcessingService(
        serviceProvider.GetRequiredService<IImportRunRepository>(),
        serviceProvider.GetRequiredService<IFundingSourceProviderRegistry>(),
        serviceProvider.GetRequiredService<IFundingOpportunityRepository>(),
        serviceProvider.GetRequiredService<TimeProvider>(),
        TimeSpan.FromSeconds(options.LeaseSeconds));
});
builder.Services.AddScoped(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<ImportWorkerOptions>>().Value;
    var identity = serviceProvider.GetRequiredService<ImportWorkerIdentity>();
    return new ImportOutboxDispatcherService(
        serviceProvider.GetRequiredService<IImportOutboxRepository>(),
        serviceProvider.GetRequiredService<IImportQueuePublisher>(),
        serviceProvider.GetRequiredService<TimeProvider>(),
        identity.LeasePrefix,
        TimeSpan.FromSeconds(options.LeaseSeconds),
        serviceProvider.GetRequiredService<ISourceDocumentExtractionQueuePublisher>());
});

builder.Build().Run();
