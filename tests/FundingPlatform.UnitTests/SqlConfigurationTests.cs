using System.Data;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.UnitTests;

public sealed class SqlConfigurationTests
{
    [Fact]
    public void Aliases_map_all_supported_environment_names()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AZURE_SQL_CONNECTION_STRING"] = "Server=sql.example;Database=funding;Integrated Security=true;",
            ["MIGRATION_EXPECTED_DATABASE_NAME"] = "risefunding-dev",
            ["MIGRATION_EXPECTED_SERVER_FQDN"] = "sql-rf-dev-demo.database.windows.net",
            ["BACKEND_API_BASE_URL"] = "http://localhost:5070",
            ["INTERNAL_API_KEY"] = "test-key",
            ["API_FOOTBALL_KEY"] = "football-key",
            ["AZURE_STORAGE_BLOB_SERVICE_URI"] = "https://storage.example.invalid",
            ["SOURCE_DOCUMENT_INCOMING_CONTAINER"] = "fp-source-incoming",
            ["SOURCE_DOCUMENT_QUARANTINE_CONTAINER"] = "fp-source-quarantine",
            ["SOURCE_DOCUMENT_TRUSTED_CONTAINER"] = "fp-source-trusted",
            ["SOURCE_DOCUMENT_MAX_BYTES"] = "26214400",
            ["SOURCE_DOCUMENT_UPLOAD_TTL_MINUTES"] = "5",
            ["SOURCE_DOCUMENT_FINALIZE_LEASE_SECONDS"] = "120",
            ["SOURCE_DOCUMENT_SCAN_TIMEOUT_SECONDS"] = "10",
            ["SOURCE_DOCUMENT_SCAN_MODE"] = "DevelopmentFake",
            ["SOURCE_DOCUMENT_DEVELOPMENT_FAKE_RESULT"] = "Clean",
            ["IMPORT_WORKER_LEASE_SECONDS"] = "1800",
            ["IMPORT_SCHEDULER_BATCH_SIZE"] = "10",
            ["IMPORT_OUTBOX_BATCH_SIZE"] = "25",
            ["GRANTS_GOV_TIMEOUT_SECONDS"] = "20",
            ["IMPORT_ALLOWED_PROVIDERS"] = "grants-gov",
            ["AUTH_ACCESS_TOKEN_MINUTES"] = "15",
            ["AUTH_REFRESH_TOKEN_DAYS"] = "30",
            ["AUTH_ADMIN_SESSION_MINUTES"] = "60"
        });

        configuration.AddFundingPlatformAliases();

        Assert.Equal(
            "Server=sql.example;Database=funding;Integrated Security=true;",
            configuration["ConnectionStrings:DefaultConnection"]);
        Assert.Equal("risefunding-dev", configuration["Migrations:ExpectedDatabaseName"]);
        Assert.Equal(
            "sql-rf-dev-demo.database.windows.net",
            configuration["Migrations:ExpectedServerFqdn"]);
        Assert.Equal("http://localhost:5070", configuration["BackendApi:BaseUrl"]);
        Assert.Equal("test-key", configuration["ApiSecurity:InternalApiKey"]);
        Assert.Equal("test-key", configuration["BackendApi:InternalApiKey"]);
        Assert.Equal("football-key", configuration["ApiFootball:ApiKey"]);
        Assert.Equal("https://storage.example.invalid", configuration["SourceDocuments:BlobServiceUri"]);
        Assert.Equal("fp-source-incoming", configuration["SourceDocuments:IncomingContainer"]);
        Assert.Equal("fp-source-quarantine", configuration["SourceDocuments:QuarantineContainer"]);
        Assert.Equal("fp-source-trusted", configuration["SourceDocuments:TrustedContainer"]);
        Assert.Equal("26214400", configuration["SourceDocuments:MaxBytes"]);
        Assert.Equal("5", configuration["SourceDocuments:UploadTtlMinutes"]);
        Assert.Equal("120", configuration["SourceDocuments:FinalizeLeaseSeconds"]);
        Assert.Equal("10", configuration["SourceDocuments:ScanTimeoutSeconds"]);
        Assert.Equal("DevelopmentFake", configuration["SourceDocuments:ScanMode"]);
        Assert.Equal("Clean", configuration["SourceDocuments:DevelopmentFakeResult"]);
        Assert.Equal("1800", configuration["ImportWorkers:LeaseSeconds"]);
        Assert.Equal("10", configuration["ImportWorkers:SchedulerBatchSize"]);
        Assert.Equal("25", configuration["ImportWorkers:OutboxBatchSize"]);
        Assert.Equal("20", configuration["ImportWorkers:GrantsGovTimeoutSeconds"]);
        Assert.Equal("grants-gov", configuration["ImportWorkers:AllowedProviders"]);
        Assert.Equal("15", configuration["Authentication:Jwt:AccessTokenMinutes"]);
        Assert.Equal("30", configuration["Authentication:RefreshToken:LifetimeDays"]);
        Assert.Equal("60", configuration["Authentication:Mfa:AdminSessionMinutes"]);
    }

    [Fact]
    public void Import_queue_storage_uses_the_same_identity_family_as_the_function_trigger()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AZURE_FUNCTIONS_ENVIRONMENT"] = "Development",
            ["AzureWebJobsStorage:accountName"] = "fpongdev1234"
        });

        var settings = ImportQueueStorageConfiguration.Resolve(configuration);

        Assert.True(settings.UsesManagedIdentity);
        Assert.Equal(
            "https://fpongdev1234.queue.core.windows.net/",
            settings.QueueServiceUri?.AbsoluteUri);
        Assert.Null(settings.DevelopmentConnectionString);
    }

    [Fact]
    public void Hosted_import_queue_storage_requires_managed_identity_credential()
    {
        var incomplete = new ConfigurationManager();
        incomplete["AZURE_FUNCTIONS_ENVIRONMENT"] = "Production";
        incomplete["AzureWebJobsStorage:accountName"] = "fpongdev1234";
        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(incomplete));

        incomplete["AzureWebJobsStorage:credential"] = "managedidentity";
        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(incomplete));

        var configured = new ConfigurationManager();
        configured["AZURE_FUNCTIONS_ENVIRONMENT"] = "Production";
        configured["AzureWebJobsStorage:accountName"] = "fpongdev1234";
        configured["AzureWebJobsStorage:credential"] = "managedidentity";
        configured["AzureWebJobsStorage:clientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";

        var settings = ImportQueueStorageConfiguration.Resolve(configured);

        Assert.Equal(
            Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89"),
            settings.ManagedIdentityClientId);
    }

    [Fact]
    public void Import_queue_storage_accepts_only_azurite_connection_strings()
    {
        var local = new ConfigurationManager();
        local["AZURE_FUNCTIONS_ENVIRONMENT"] = "Development";
        local["AzureWebJobsStorage"] = "UseDevelopmentStorage=true";
        var localSettings = ImportQueueStorageConfiguration.Resolve(local);
        Assert.Equal("UseDevelopmentStorage=true", localSettings.DevelopmentConnectionString);

        var unsafeConfiguration = new ConfigurationManager();
        unsafeConfiguration["AzureWebJobsStorage"] =
            "DefaultEndpointsProtocol=https;AccountName=secret;AccountKey=secret";

        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(unsafeConfiguration));
    }

    [Fact]
    public void Import_queue_storage_rejects_custom_alias_without_host_configuration()
    {
        var configuration = new ConfigurationManager();
        configuration["AZURE_STORAGE_QUEUE_SERVICE_URI"] =
            "https://fpongdev1234.queue.core.windows.net";
        configuration.AddFundingPlatformAliases();

        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(configuration));
    }

    [Fact]
    public void Import_queue_storage_requires_matching_queue_and_blob_endpoints()
    {
        var incomplete = new ConfigurationManager();
        incomplete["AZURE_FUNCTIONS_ENVIRONMENT"] = "Development";
        incomplete["AzureWebJobsStorage:queueServiceUri"] =
            "https://fpongdev1234.queue.core.windows.net";
        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(incomplete));

        var mismatched = new ConfigurationManager();
        mismatched["AZURE_FUNCTIONS_ENVIRONMENT"] = "Development";
        mismatched["AzureWebJobsStorage:queueServiceUri"] =
            "https://fpongdev1234.queue.core.windows.net";
        mismatched["AzureWebJobsStorage:blobServiceUri"] =
            "https://anotheraccount.blob.core.windows.net";
        Assert.Throws<InvalidOperationException>(() =>
            ImportQueueStorageConfiguration.Resolve(mismatched));
    }

    [Fact]
    public void Document_extraction_queue_is_a_distinct_identity_connection_in_azure()
    {
        var configuration = new ConfigurationManager();
        configuration["AZURE_FUNCTIONS_ENVIRONMENT"] = "Production";
        configuration["AzureWebJobsStorage:accountName"] = "hostonly123";
        configuration["AzureWebJobsStorage:credential"] = "managedidentity";
        configuration["AzureWebJobsStorage:clientId"] =
            "4a8d5ca8-44e4-49b7-9cb7-269322662947";

        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration));

        configuration["DocumentExtractionQueueStorage:accountName"] = "sharedqueue123";
        configuration["DocumentExtractionQueueStorage:credential"] = "managedidentity";
        configuration["DocumentExtractionQueueStorage:clientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";
        configuration["DocumentExtractionQueueStorage:senderClientId"] =
            "ac6f0709-4c22-4b20-a91b-359f51c6db41";

        var settings = DocumentExtractionQueueStorageConfiguration.Resolve(configuration);

        Assert.Equal(
            "https://sharedqueue123.queue.core.windows.net/",
            settings.QueueServiceUri?.AbsoluteUri);
        Assert.Equal(
            Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89"),
            settings.ManagedIdentityClientId);
        Assert.Equal(
            Guid.Parse("ac6f0709-4c22-4b20-a91b-359f51c6db41"),
            settings.SenderManagedIdentityClientId);

        configuration["DocumentExtractionQueueStorage:accountName"] = "hostonly123";
        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration));
    }

    [Fact]
    public void Extraction_identity_client_id_is_preserved_for_queue_and_blob_credentials()
    {
        var configuration = new ConfigurationManager();
        configuration["AZURE_FUNCTIONS_ENVIRONMENT"] = "Production";
        configuration["AzureWebJobsStorage:accountName"] = "hostonly123";
        configuration["AzureWebJobsStorage:credential"] = "managedidentity";
        configuration["AzureWebJobsStorage:clientId"] =
            "4a8d5ca8-44e4-49b7-9cb7-269322662947";
        configuration["DocumentExtractionQueueStorage:accountName"] = "sharedqueue123";
        configuration["DocumentExtractionQueueStorage:credential"] = "managedidentity";
        configuration["DocumentExtractionQueueStorage:clientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";
        configuration["DocumentExtractionQueueStorage:senderClientId"] =
            "ac6f0709-4c22-4b20-a91b-359f51c6db41";

        var settings =
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration);

        Assert.Equal(
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89",
            settings.ManagedIdentityClientId?.ToString("D"));
        Assert.Equal(
            "ac6f0709-4c22-4b20-a91b-359f51c6db41",
            settings.SenderManagedIdentityClientId?.ToString("D"));
    }

    [Fact]
    public void Hosted_extraction_requires_one_explicit_user_assigned_identity()
    {
        var withoutClientId = new DocumentExtractionQueueStorageSettings(
            null,
            new Uri("https://sharedqueue123.queue.core.windows.net"));
        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration
                .RequireExtractionManagedIdentity(withoutClientId, "Production"));

        var clientId = Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89");
        var configured = withoutClientId with
        {
            ManagedIdentityClientId = clientId,
            SenderManagedIdentityClientId =
                Guid.Parse("ac6f0709-4c22-4b20-a91b-359f51c6db41")
        };
        Assert.Equal(clientId,
            DocumentExtractionQueueStorageConfiguration
                .RequireExtractionManagedIdentity(configured, "Production"));
        Assert.Null(DocumentExtractionQueueStorageConfiguration
            .RequireExtractionManagedIdentity(
                new DocumentExtractionQueueStorageSettings(
                    "UseDevelopmentStorage=true", null),
                "Development"));
    }

    [Fact]
    public void Hosted_document_extraction_sender_has_a_distinct_identity()
    {
        var consumerId = Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89");
        var senderId = Guid.Parse("ac6f0709-4c22-4b20-a91b-359f51c6db41");
        var baseSettings = new DocumentExtractionQueueStorageSettings(
            null,
            new Uri("https://sharedqueue123.queue.core.windows.net"),
            consumerId,
            senderId);

        Assert.Equal(senderId,
            DocumentExtractionQueueStorageConfiguration
                .RequireSenderManagedIdentity(baseSettings, "Production"));
        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration
                .RequireSenderManagedIdentity(
                    baseSettings with { SenderManagedIdentityClientId = consumerId },
                    "Production"));
    }

    [Fact]
    public void Hosted_document_extraction_identities_are_distinct_from_host_identity()
    {
        var configuration = new ConfigurationManager();
        configuration["AZURE_FUNCTIONS_ENVIRONMENT"] = "Production";
        configuration["AzureWebJobsStorage:accountName"] = "hostonly123";
        configuration["AzureWebJobsStorage:credential"] = "managedidentity";
        configuration["AzureWebJobsStorage:clientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";
        configuration["DocumentExtractionQueueStorage:accountName"] = "sharedqueue123";
        configuration["DocumentExtractionQueueStorage:credential"] = "managedidentity";
        configuration["DocumentExtractionQueueStorage:clientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";
        configuration["DocumentExtractionQueueStorage:senderClientId"] =
            "ac6f0709-4c22-4b20-a91b-359f51c6db41";

        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration));

        configuration["DocumentExtractionQueueStorage:clientId"] =
            "4a8d5ca8-44e4-49b7-9cb7-269322662947";
        configuration["DocumentExtractionQueueStorage:senderClientId"] =
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89";
        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration));

        configuration["DocumentExtractionQueueStorage:senderClientId"] =
            "ac6f0709-4c22-4b20-a91b-359f51c6db41";
        var settings =
            DocumentExtractionQueueStorageConfiguration.Resolve(configuration);

        var hostId = Guid.Parse(configuration["AzureWebJobsStorage:clientId"]!);
        Assert.NotEqual(hostId, settings.ManagedIdentityClientId);
        Assert.NotEqual(hostId, settings.SenderManagedIdentityClientId);
    }

    [Fact]
    public void Hosted_general_worker_SQL_identity_is_the_host_identity()
    {
        var hostClientId = Guid.Parse("4a8d5ca8-44e4-49b7-9cb7-269322662947");
        var configuration = new ConfigurationManager();
        configuration["ConnectionStrings:DefaultConnection"] =
            "Server=tcp:funding.database.windows.net,1433;Initial Catalog=res;" +
            "Encrypt=True;TrustServerCertificate=False;" +
            "Authentication=Active Directory Default;";

        var factory = new UserAssignedManagedIdentitySqlConnectionFactory(
            configuration, hostClientId);
        using var connection = factory.CreateConnection();
        var parsed = new SqlConnectionStringBuilder(connection.ConnectionString);

        Assert.Equal(hostClientId.ToString("D"), parsed.UserID);
        Assert.NotEqual(
            "2c7e54ab-2a4d-477a-86ce-bbcd2882cd89", parsed.UserID);
        Assert.NotEqual(
            "ac6f0709-4c22-4b20-a91b-359f51c6db41", parsed.UserID);
    }

    [Fact]
    public void Extraction_SQL_factory_pins_the_same_user_assigned_identity()
    {
        var clientId = Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89");
        var configuration = new ConfigurationManager();
        configuration["ConnectionStrings:DefaultConnection"] =
            "Server=tcp:funding.database.windows.net,1433;Initial Catalog=res;" +
            "Encrypt=True;TrustServerCertificate=False;" +
            "Authentication=Active Directory Default;";

        var factory = new UserAssignedManagedIdentitySqlConnectionFactory(
            configuration, clientId);
        using var connection = factory.CreateConnection();
        var result = new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(
            connection.ConnectionString);

        Assert.Equal(
            Microsoft.Data.SqlClient.SqlAuthenticationMethod.ActiveDirectoryManagedIdentity,
            result.Authentication);
        Assert.Equal(clientId.ToString("D"), result.UserID);
        Assert.False(result.IntegratedSecurity);
        Assert.Empty(result.Password);
        Assert.DoesNotContain(
            "Password=", connection.ConnectionString, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(
            "Pwd=", connection.ConnectionString, StringComparison.OrdinalIgnoreCase);
        Assert.False(result.TrustServerCertificate);
    }

    [Fact]
    public void Azure_runtime_credential_is_managed_identity_only_outside_development()
    {
        var clientId = Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89");

        Assert.IsType<Azure.Identity.ManagedIdentityCredential>(
            AzureRuntimeCredentialFactory.Create(clientId, "Production"));
        Assert.IsType<Azure.Identity.ManagedIdentityCredential>(
            AzureRuntimeCredentialFactory.Create(null, "Production"));
        Assert.IsType<Azure.Identity.DefaultAzureCredential>(
            AzureRuntimeCredentialFactory.Create(clientId, "Development"));
    }

    [Theory]
    [InlineData("Authentication=Sql Password;User Id=worker;Password=secret;Encrypt=True;TrustServerCertificate=False")]
    [InlineData("Authentication=Active Directory Managed Identity;User Id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa;Encrypt=True;TrustServerCertificate=False")]
    [InlineData("Authentication=Active Directory Default;Encrypt=False;TrustServerCertificate=False")]
    [InlineData("Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=True")]
    public void Extraction_SQL_factory_rejects_identity_or_transport_drift(string suffix)
    {
        var configuration = new ConfigurationManager();
        configuration["ConnectionStrings:DefaultConnection"] =
            $"Server=tcp:funding.database.windows.net,1433;Initial Catalog=res;{suffix};";

        Assert.Throws<InvalidOperationException>(() =>
            new UserAssignedManagedIdentitySqlConnectionFactory(
                configuration,
                Guid.Parse("2c7e54ab-2a4d-477a-86ce-bbcd2882cd89")));
    }

    [Fact]
    public void Document_extraction_queue_may_share_only_local_azurite_bytes()
    {
        var configuration = new ConfigurationManager();
        configuration["AZURE_FUNCTIONS_ENVIRONMENT"] = "Development";
        configuration["AzureWebJobsStorage"] = "UseDevelopmentStorage=true";

        var settings = DocumentExtractionQueueStorageConfiguration.Resolve(configuration);

        Assert.Equal("UseDevelopmentStorage=true", settings.DevelopmentConnectionString);
        Assert.False(settings.UsesManagedIdentity);
    }

    [Fact]
    public void Extraction_host_storage_cannot_be_the_document_blob_account_in_azure()
    {
        var host = new ImportQueueStorageSettings(
            null, new Uri("https://hostonly123.queue.core.windows.net"));
        DocumentExtractionQueueStorageConfiguration
            .EnsureHostStorageIsolatedFromDocumentBlobs(
                host,
                new Uri("https://documents123.blob.core.windows.net"),
                "Production");

        Assert.Throws<InvalidOperationException>(() =>
            DocumentExtractionQueueStorageConfiguration
                .EnsureHostStorageIsolatedFromDocumentBlobs(
                    host,
                    new Uri("https://hostonly123.blob.core.windows.net"),
                    "Production"));
    }

    [Fact]
    public void Canonical_configuration_takes_precedence_over_alias()
    {
        var configuration = new ConfigurationManager();
        configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["AZURE_SQL_CONNECTION_STRING"] = "Server=alias;Database=funding;Integrated Security=true;",
            ["ConnectionStrings:DefaultConnection"] = "Server=canonical;Database=funding;Integrated Security=true;"
        });

        configuration.AddFundingPlatformAliases();

        Assert.Equal(
            "Server=canonical;Database=funding;Integrated Security=true;",
            configuration["ConnectionStrings:DefaultConnection"]);
    }

    [Fact]
    public void Factory_returns_a_new_closed_connection_each_time()
    {
        var configuration = new ConfigurationManager();
        configuration["ConnectionStrings:DefaultConnection"] =
            "Server=sql.example;Database=funding;Integrated Security=true;";
        var factory = new SqlConnectionFactory(configuration);

        using SqlConnection first = factory.CreateConnection();
        using SqlConnection second = factory.CreateConnection();

        Assert.NotSame(first, second);
        Assert.Equal(ConnectionState.Closed, first.State);
        Assert.Equal(ConnectionState.Closed, second.State);
    }

    [Fact]
    public void Factory_missing_configuration_error_does_not_contain_a_connection_string()
    {
        var exception = Assert.Throws<InvalidOperationException>(
            () => new SqlConnectionFactory(new ConfigurationManager()));

        Assert.Contains(SqlConnectionFactory.ConfigurationKey, exception.Message);
        Assert.DoesNotContain("Server=", exception.Message, StringComparison.OrdinalIgnoreCase);
    }
}
