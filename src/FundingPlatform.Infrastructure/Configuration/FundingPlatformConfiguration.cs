using Microsoft.Extensions.Configuration;

namespace FundingPlatform.Infrastructure.Configuration;

public static class FundingPlatformConfiguration
{
    private static readonly (string Source, string Target)[] Aliases =
    [
        ("AZURE_SQL_CONNECTION_STRING", "ConnectionStrings:DefaultConnection"),
        ("BACKEND_API_BASE_URL", "BackendApi:BaseUrl"),
        ("INTERNAL_API_KEY", "ApiSecurity:InternalApiKey"),
        ("INTERNAL_API_KEY", "BackendApi:InternalApiKey"),
        ("API_FOOTBALL_KEY", "ApiFootball:ApiKey"),
        ("AZURE_KEY_VAULT_URI", "AzureSecurity:KeyVaultUri"),
        ("KEY_VAULT_URI", "AzureSecurity:KeyVaultUri"),
        ("AZURE_STORAGE_DATA_PROTECTION_BLOB_URI", "AzureSecurity:DataProtectionBlobUri"),
        ("AZURE_KEY_VAULT_DATA_PROTECTION_KEY_URI", "AzureSecurity:DataProtectionKeyUri"),
        ("AZURE_STORAGE_BLOB_SERVICE_URI", "SourceDocuments:BlobServiceUri"),
        ("IMPORT_WORKER_LEASE_SECONDS", "ImportWorkers:LeaseSeconds"),
        ("IMPORT_SCHEDULER_BATCH_SIZE", "ImportWorkers:SchedulerBatchSize"),
        ("IMPORT_OUTBOX_BATCH_SIZE", "ImportWorkers:OutboxBatchSize"),
        ("GRANTS_GOV_TIMEOUT_SECONDS", "ImportWorkers:GrantsGovTimeoutSeconds"),
        ("IMPORT_ALLOWED_PROVIDERS", "ImportWorkers:AllowedProviders"),
        ("CONTENT_RETENTION_BATCH_SIZE", "ContentRetention:BatchSize"),
        ("CONTENT_RETENTION_SOURCE_DOCUMENT_BATCH_SIZE", "ContentRetention:SourceDocumentBatchSize"),
        ("CONTENT_RETENTION_SOURCE_DOCUMENT_LEASE_SECONDS", "ContentRetention:SourceDocumentLeaseSeconds"),
        ("SOURCE_DOCUMENT_INCOMING_CONTAINER", "SourceDocuments:IncomingContainer"),
        ("SOURCE_DOCUMENT_QUARANTINE_CONTAINER", "SourceDocuments:QuarantineContainer"),
        ("SOURCE_DOCUMENT_TRUSTED_CONTAINER", "SourceDocuments:TrustedContainer"),
        ("SOURCE_DOCUMENT_MAX_BYTES", "SourceDocuments:MaxBytes"),
        ("SOURCE_DOCUMENT_UPLOAD_TTL_MINUTES", "SourceDocuments:UploadTtlMinutes"),
        ("SOURCE_DOCUMENT_FINALIZE_LEASE_SECONDS", "SourceDocuments:FinalizeLeaseSeconds"),
        ("SOURCE_DOCUMENT_SCAN_TIMEOUT_SECONDS", "SourceDocuments:ScanTimeoutSeconds"),
        ("SOURCE_DOCUMENT_SCAN_MODE", "SourceDocuments:ScanMode"),
        ("SOURCE_DOCUMENT_DEVELOPMENT_FAKE_RESULT", "SourceDocuments:DevelopmentFakeResult"),
        ("DOCUMENT_EXTRACTION_MAX_BYTES", "DocumentExtraction:MaximumBytes"),
        ("DOCUMENT_EXTRACTION_MAX_PAGES", "DocumentExtraction:MaximumPages"),
        ("DOCUMENT_EXTRACTION_MAX_CHARACTERS", "DocumentExtraction:MaximumCharacters"),
        ("DOCUMENT_EXTRACTION_MAX_UTF8_BYTES", "DocumentExtraction:MaximumUtf8Bytes"),
        ("DOCUMENT_EXTRACTION_MAX_STACK_DEPTH", "DocumentExtraction:MaximumStackDepth"),
        ("DOCUMENT_EXTRACTION_TIMEOUT_SECONDS", "DocumentExtraction:TimeoutSeconds"),
        ("DOCUMENT_EXTRACTION_LEASE_SECONDS", "DocumentExtraction:LeaseSeconds"),
        ("DOCUMENT_EXTRACTION_WATCHDOG_BATCH_SIZE", "DocumentExtraction:WatchdogBatchSize"),
        ("DEFENDER_EVENT_GRID_ENABLED", "DefenderEventGrid:Enabled"),
        ("DEFENDER_EVENT_GRID_TENANT_ID", "DefenderEventGrid:TenantId"),
        ("DEFENDER_EVENT_GRID_AUDIENCE", "DefenderEventGrid:Audience"),
        ("DEFENDER_EVENT_GRID_CALLER_APPLICATION_ID", "DefenderEventGrid:AllowedCallerApplicationId"),
        ("DEFENDER_EVENT_GRID_CALLER_OBJECT_ID", "DefenderEventGrid:AllowedCallerObjectId"),
        ("DEFENDER_EVENT_GRID_TOPIC_RESOURCE_ID", "DefenderEventGrid:ExpectedTopicResourceId"),
        ("DEFENDER_EVENT_GRID_SUBSCRIPTION_NAME", "DefenderEventGrid:ExpectedSubscriptionName"),
        ("DEFENDER_EVENT_GRID_STORAGE_RESOURCE_ID", "DefenderEventGrid:StorageAccountResourceId"),
        ("DEFENDER_PENDING_SCAN_TIMEOUT_MINUTES", "DefenderEventGrid:PendingScanTimeoutMinutes"),
        ("DEFENDER_WATCHDOG_BATCH_SIZE", "DefenderEventGrid:WatchdogBatchSize"),
        ("OFFICIAL_RSS_ENABLED", "OfficialRss:Enabled"),
        ("OFFICIAL_RSS_FEED_URI", "OfficialRss:FeedUri"),
        ("OFFICIAL_RSS_ALLOWED_HOSTS", "OfficialRss:AllowedHosts"),
        ("OFFICIAL_RSS_SOURCE_NAME", "OfficialRss:SourceName"),
        ("OFFICIAL_RSS_SPONSOR_NAME", "OfficialRss:SponsorName"),
        ("OFFICIAL_RSS_LICENSE_NAME", "OfficialRss:LicenseName"),
        ("OFFICIAL_RSS_LICENSE_URI", "OfficialRss:LicenseUri"),
        ("OFFICIAL_RSS_COMPLIANCE_APPROVED", "OfficialRss:ComplianceApproved"),
        ("OFFICIAL_RSS_ROBOTS_POLICY", "OfficialRss:RobotsPolicy"),
        ("OFFICIAL_RSS_ROBOTS_POLICY_VERSION", "OfficialRss:RobotsPolicyVersion"),
        ("OFFICIAL_RSS_MINIMUM_DELAY_SECONDS", "OfficialRss:MinimumDelaySeconds"),
        ("OFFICIAL_RSS_TIMEOUT_SECONDS", "OfficialRss:TimeoutSeconds"),
        ("OFFICIAL_RSS_MAXIMUM_BYTES", "OfficialRss:MaximumBytes"),
        ("OFFICIAL_RSS_MAXIMUM_CHARACTERS", "OfficialRss:MaximumCharacters"),
        ("OFFICIAL_RSS_MAXIMUM_ITEMS", "OfficialRss:MaximumItems"),
        ("OFFICIAL_RSS_USER_AGENT", "OfficialRss:UserAgent"),
        ("SEMANTIC_ENABLED", "Semantic:Enabled"),
        ("SEMANTIC_SHADOW_ONLY", "Semantic:ShadowOnly"),
        ("SEMANTIC_DIMENSIONS", "Semantic:Dimensions"),
        ("SEMANTIC_BATCH_SIZE", "Semantic:BatchSize"),
        ("SEMANTIC_LEASE_SECONDS", "Semantic:LeaseSeconds"),
        ("SEMANTIC_TIMEOUT_SECONDS", "Semantic:TimeoutSeconds"),
        ("AZURE_COMMUNICATION_SERVICES_ENDPOINT", "Email:Endpoint"),
        ("EMAIL_FROM_ADDRESS", "Email:FromAddress"),
        ("FRONTEND_BASE_URL", "Email:FrontendBaseUrl"),
        ("JWT_SECRET", "Authentication:Jwt:SigningKey"),
        ("JWT_ISSUER", "Authentication:Jwt:Issuer"),
        ("JWT_AUDIENCE", "Authentication:Jwt:Audience"),
        ("AUTH_ACCESS_TOKEN_MINUTES", "Authentication:Jwt:AccessTokenMinutes"),
        ("AUTH_REFRESH_TOKEN_DAYS", "Authentication:RefreshToken:LifetimeDays"),
        ("AUTH_ADMIN_SESSION_MINUTES", "Authentication:Mfa:AdminSessionMinutes"),
        ("SECURITY_IP_HASH_PEPPER", "Authentication:SecurityHash:IpHashPepper"),
        ("SECURITY_RECOVERY_CODE_PEPPER", "Authentication:SecurityHash:RecoveryCodePepper"),
        ("ENTRA_SSO_ENABLED", "Authentication:External:Entra:Enabled"),
        ("ENTRA_SSO_TENANT_ID", "Authentication:External:Entra:TenantId"),
        ("ENTRA_SSO_CLIENT_ID", "Authentication:External:Entra:ClientId"),
        ("ENTRA_SSO_CLIENT_SECRET", "Authentication:External:Entra:ClientSecret")
    ];

    public static ConfigurationManager CreateFromEnvironment()
    {
        var configuration = new ConfigurationManager();
        configuration.AddEnvironmentVariables();
        configuration.AddFundingPlatformAliases();
        return configuration;
    }

    public static ConfigurationManager AddFundingPlatformAliases(
        this ConfigurationManager configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var aliasValues = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);

        foreach (var (source, target) in Aliases)
        {
            if (string.IsNullOrWhiteSpace(configuration[target]) &&
                !string.IsNullOrWhiteSpace(configuration[source]))
            {
                aliasValues[target] = configuration[source];
            }
        }

        if (aliasValues.Count > 0)
        {
            configuration.AddInMemoryCollection(aliasValues);
        }

        return configuration;
    }
}
