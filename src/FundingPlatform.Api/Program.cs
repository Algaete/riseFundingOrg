using System.Security.Claims;
using System.Threading.RateLimiting;
using Azure.Communication.Email;
using Azure.Core;
using Azure.Extensions.AspNetCore.Configuration.Secrets;
using Azure.Storage.Blobs;
using FundingPlatform.Api.Configuration;
using FundingPlatform.Api.Authorization;
using FundingPlatform.Api.Endpoints;
using FundingPlatform.Api.Health;
using FundingPlatform.Api.Middleware;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Application.Alerts;
using FundingPlatform.Application.Billing;
using FundingPlatform.Application.Applications;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Application.Imports;
using FundingPlatform.Application.Matching;
using FundingPlatform.Application.Networking;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Application.Organizations;
using FundingPlatform.Application.Marketplace;
using FundingPlatform.Application.Projects;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Contracts;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Billing;
using FundingPlatform.Infrastructure.Identity;
using FundingPlatform.Infrastructure.Identity.Configuration;
using FundingPlatform.Infrastructure.Identity.Cryptography;
using FundingPlatform.Infrastructure.Identity.Email;
using FundingPlatform.Infrastructure.Identity.Persistence;
using FundingPlatform.Infrastructure.Persistence.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Alerts;
using FundingPlatform.Infrastructure.Persistence.Billing;
using FundingPlatform.Infrastructure.Persistence.Applications;
using FundingPlatform.Infrastructure.Persistence.Imports;
using FundingPlatform.Infrastructure.Persistence.Matching;
using FundingPlatform.Infrastructure.Persistence.Networking;
using FundingPlatform.Infrastructure.Persistence.Semantics;
using FundingPlatform.Infrastructure.Persistence.Organizations;
using FundingPlatform.Infrastructure.Persistence.Marketplace;
using FundingPlatform.Infrastructure.Persistence.Projects;
using FundingPlatform.Infrastructure.Persistence.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.Infrastructure.SourceDocuments.Configuration;
using FundingPlatform.Infrastructure.SourceDocuments.Cryptography;
using FundingPlatform.Infrastructure.SourceDocuments.Inspection;
using FundingPlatform.Infrastructure.SourceDocuments.Scanning;
using FundingPlatform.Infrastructure.SourceDocuments.Storage;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Serilog;

LocalEnvironmentLoader.TryLoad();

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options =>
    options.Limits.MaxRequestBodySize = 1024 * 1024);
builder.Configuration.AddFundingPlatformAliases();

var hasManagedIdentityClientId = Guid.TryParse(
    builder.Configuration["AZURE_CLIENT_ID"],
    out var managedIdentityClientId);
if (!builder.Environment.IsDevelopment() &&
    !builder.Environment.IsEnvironment("Testing") &&
    !hasManagedIdentityClientId)
{
    throw new InvalidOperationException(
        "AZURE_CLIENT_ID debe identificar explícitamente la UAMI de la API.");
}

var azureCredential = AzureRuntimeCredentialFactory.Create(
    hasManagedIdentityClientId ? managedIdentityClientId : null,
    builder.Environment.EnvironmentName);

if (!builder.Environment.IsEnvironment("Testing"))
{
    var keyVaultUri = builder.Configuration["AzureSecurity:KeyVaultUri"];
    if (string.IsNullOrWhiteSpace(keyVaultUri) ||
        !Uri.TryCreate(keyVaultUri, UriKind.Absolute, out var keyVaultEndpoint))
    {
        throw new InvalidOperationException("AzureSecurity:KeyVaultUri no está configurada.");
    }

    builder.Configuration.AddAzureKeyVault(keyVaultEndpoint, azureCredential);
    builder.Configuration.AddEnvironmentVariables();
    builder.Configuration.AddFundingPlatformAliases();
}

builder.Host.UseSerilog((context, services, loggerConfiguration) =>
    loggerConfiguration
        .ReadFrom.Configuration(context.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "FundingPlatform.Api")
        .WriteTo.Console());

builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        context.ProblemDetails.Extensions["correlationId"] = context.HttpContext.TraceIdentifier;
        context.ProblemDetails.Extensions["traceId"] = context.HttpContext.TraceIdentifier;
    };
});
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddCors();
builder.Services.AddSingleton<TokenCredential>(azureCredential);
builder.Services.AddSingleton(TimeProvider.System);
if (!builder.Environment.IsDevelopment() &&
    !builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddSingleton<ISqlConnectionFactory>(_ =>
        new UserAssignedManagedIdentitySqlConnectionFactory(
            builder.Configuration,
            managedIdentityClientId));
}
else
{
    builder.Services.AddSingleton<ISqlConnectionFactory, SqlConnectionFactory>();
}
builder.Services.AddSingleton<SqlConnectionVerifier>();
builder.Services.AddScoped<IFundingOpportunityRepository, SqlFundingOpportunityRepository>();
builder.Services.AddScoped<FundingOpportunityCatalogService>();
builder.Services.AddScoped<IFundingOpportunityWorkspaceRepository,
    SqlFundingOpportunityWorkspaceRepository>();
builder.Services.AddScoped<FundingOpportunityWorkspaceService>();
builder.Services.AddScoped<ISavedSearchAlertRepository, SqlSavedSearchAlertRepository>();
builder.Services.AddScoped<SavedSearchAlertService>();
builder.Services.AddScoped<IFunderRepository, SqlFunderRepository>();
builder.Services.AddScoped<FunderEditorialService>();
builder.Services.AddScoped<IFundingOpportunityEditorialRepository,
    SqlFundingOpportunityEditorialRepository>();
builder.Services.AddScoped<FundingOpportunityEditorialService>();
builder.Services.AddScoped<IFundingDuplicateReviewRepository,
    SqlFundingDuplicateReviewRepository>();
builder.Services.AddScoped<FundingDuplicateReviewService>();
builder.Services.AddScoped<IFundingSourceAdminRepository, SqlFundingSourceAdminRepository>();
builder.Services.AddScoped<FundingSourceAdminService>();
builder.Services.AddScoped<IImportRunService, ImportRunService>();
builder.Services.AddScoped<IImportRunRepository, SqlImportRunRepository>();
builder.Services.AddScoped<IOrganizationRepository, SqlOrganizationRepository>();
builder.Services.AddScoped<OrganizationProfileService>();
builder.Services.AddScoped<IProjectRepository, SqlProjectRepository>();
builder.Services.AddScoped<ProjectService>();
builder.Services.AddScoped<ProjectWorkflowService>();
builder.Services.AddScoped<IMarketplaceRepository, SqlMarketplaceRepository>();
builder.Services.AddScoped<MarketplaceService>();
builder.Services.AddScoped<IFundingApplicationRepository, SqlFundingApplicationRepository>();
builder.Services.AddScoped<FundingApplicationService>();
builder.Services.AddScoped<INetworkingRepository, SqlNetworkingRepository>();
builder.Services.AddScoped<NetworkingService>();
builder.Services.AddScoped<IBillingRepository, SqlBillingRepository>();
builder.Services.AddScoped<BillingService>();
builder.Services.AddScoped<PaymentWebhookIngressService>();
builder.Services.AddScoped<IProjectMatchingRepository, SqlProjectMatchingRepository>();
builder.Services.AddScoped<ProjectMatchingService>();
builder.Services.AddScoped<ISemanticEvaluationRepository, SqlSemanticProcessingRepository>();
builder.Services.AddScoped<SemanticEvaluationAdministrationService>();
builder.Services.AddScoped<IAiExplanationAdministrationRepository,
    SqlSemanticProcessingRepository>();
builder.Services.AddScoped<AiExplanationAdministrationService>();
builder.Services.AddScoped<ISourceDocumentRepository, SqlSourceDocumentRepository>();
builder.Services.AddScoped<ISourceDocumentExtractionRepository,
    SqlSourceDocumentExtractionRepository>();
builder.Services.AddScoped<SourceDocumentService>();
builder.Services.AddScoped<SourceDocumentExtractionAdminService>();
builder.Services.AddSingleton<ISourceDocumentCompletionTokenService,
    SourceDocumentCompletionTokenService>();
builder.Services.AddSingleton<ISourceDocumentContentInspector, StreamingPdfContentInspector>();
builder.Services.AddSingleton<ISourceDocumentScanner, ConfiguredSourceDocumentScanner>();
builder.Services.AddSingleton<ISourceDocumentBlobStore, AzureSourceDocumentBlobStore>();
builder.Services.AddScoped<SqlAuthenticationRepository>();
builder.Services.AddScoped<SecureTokenGenerator>();
builder.Services.AddSingleton<JwtTokenIssuer>();
builder.Services.AddSingleton<IAuthorizationHandler, RecentMfaHandler>();

builder.Services
    .AddOptions<SemanticOptions>()
    .Bind(builder.Configuration.GetSection(SemanticOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<SemanticOptions>, SemanticOptionsValidator>();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<SemanticOptions>>().Value.ToPolicy());
builder.Services
    .AddOptions<AiExplanationOptions>()
    .Bind(builder.Configuration.GetSection(AiExplanationOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<AiExplanationOptions>,
    AiExplanationOptionsValidator>();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<AiExplanationOptions>>().Value.ToPolicy());
builder.Services
    .AddOptions<AuthenticationOptions>()
    .Bind(builder.Configuration.GetSection(AuthenticationOptions.SectionName))
    .Validate(AuthenticationOptions.IsValid, "La configuración criptográfica de autenticación no es válida.")
    .ValidateOnStart();
builder.Services
    .AddOptions<AzureSecurityOptions>()
    .Bind(builder.Configuration.GetSection(AzureSecurityOptions.SectionName))
    .Validate(
        options => builder.Environment.IsEnvironment("Testing") || AzureSecurityOptions.IsValid(options),
        "La configuración AzureSecurity no es válida.")
    .ValidateOnStart();
builder.Services
    .AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection(EmailOptions.SectionName))
    .Validate(EmailOptions.IsValid, "La configuración Email no es válida.")
    .ValidateOnStart();
builder.Services
    .AddOptions<AlertOptions>()
    .Bind(builder.Configuration.GetSection(AlertOptions.SectionName))
    .Validate(options => AlertOptions.IsValid(
        options,
        builder.Configuration.GetSection(EmailOptions.SectionName).Get<EmailOptions>() ??
            new EmailOptions()), "La configuración Alerts no es válida.")
    .ValidateOnStart();
builder.Services.AddSingleton(serviceProvider =>
{
    var alerts = serviceProvider.GetRequiredService<IOptions<AlertOptions>>().Value;
    var email = serviceProvider.GetRequiredService<IOptions<EmailOptions>>().Value;
    var policy = alerts.ToPolicy(email);
    policy.EnsureValid();
    return policy;
});
builder.Services.AddSingleton<AlertUnsubscribeTokenService>();
builder.Services
    .AddOptions<BillingOptions>()
    .Bind(builder.Configuration.GetSection(BillingOptions.SectionName))
    .Validate(options => BillingOptions.IsValid(options, builder.Environment.EnvironmentName),
        "La configuración Billing no es válida o no está restringida a sandbox.")
    .ValidateOnStart();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<BillingOptions>>().Value.ToPolicy());
builder.Services.AddSingleton<IPaymentWebhookVerifier, MercadoPagoWebhookVerifier>();
builder.Services.AddHttpClient<MercadoPagoPaymentGateway>((serviceProvider, client) =>
{
    var options = serviceProvider.GetRequiredService<IOptions<BillingOptions>>().Value;
    client.BaseAddress = new Uri(options.ApiBaseUri);
    client.Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds);
});
builder.Services.AddScoped<DevelopmentPaymentGateway>();
builder.Services.AddScoped<IPaymentGateway>(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<BillingOptions>>().Value;
    return options.GatewayMode == "DevelopmentFake"
        ? serviceProvider.GetRequiredService<DevelopmentPaymentGateway>()
        : serviceProvider.GetRequiredService<MercadoPagoPaymentGateway>();
});
builder.Services
    .AddOptions<SourceDocumentOptions>()
    .Bind(builder.Configuration.GetSection(SourceDocumentOptions.SectionName))
    .Validate(
        options => SourceDocumentOptions.IsValid(options, builder.Environment.EnvironmentName),
        "La configuración SourceDocuments no es válida.")
    .ValidateOnStart();
builder.Services
    .AddOptions<SourceDocumentExtractionOptions>()
    .Bind(builder.Configuration.GetSection(SourceDocumentExtractionOptions.SectionName))
    .ValidateOnStart();
builder.Services.AddSingleton<IValidateOptions<SourceDocumentExtractionOptions>,
    SourceDocumentExtractionOptionsValidator>();
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<SourceDocumentOptions>>().Value.ToPolicy());
builder.Services.AddSingleton(serviceProvider =>
    serviceProvider.GetRequiredService<IOptions<SourceDocumentExtractionOptions>>().Value.ToPolicy());
builder.Services.AddSingleton(serviceProvider =>
{
    var options = serviceProvider.GetRequiredService<IOptions<SourceDocumentOptions>>().Value;
    var credential = serviceProvider.GetRequiredService<TokenCredential>();
    return new BlobServiceClient(new Uri(options.BlobServiceUri), credential);
});

var dataProtection = builder.Services
    .AddDataProtection()
    .SetApplicationName("FundingPlatform")
    .SetDefaultKeyLifetime(TimeSpan.FromDays(90));
if (builder.Environment.IsEnvironment("Testing"))
{
    dataProtection.UseEphemeralDataProtectionProvider();
}
else
{
    var dataProtectionBlobUri = builder.Configuration["AzureSecurity:DataProtectionBlobUri"];
    var dataProtectionKeyUri = builder.Configuration["AzureSecurity:DataProtectionKeyUri"];
    if (!Uri.TryCreate(dataProtectionBlobUri, UriKind.Absolute, out var blobUri) ||
        !Uri.TryCreate(dataProtectionKeyUri, UriKind.Absolute, out var protectionKeyUri))
    {
        throw new InvalidOperationException("Las URI de Data Protection no están configuradas.");
    }

    dataProtection
        .PersistKeysToAzureBlobStorage(blobUri, azureCredential)
        .ProtectKeysWithAzureKeyVault(protectionKeyUri, azureCredential);
}

builder.Services
    .AddIdentityCore<PlatformUser>(options =>
    {
        options.Password.RequiredLength = 12;
        options.Password.RequiredUniqueChars = 4;
        options.Password.RequireDigit = false;
        options.Password.RequireLowercase = false;
        options.Password.RequireNonAlphanumeric = false;
        options.Password.RequireUppercase = false;
        options.Lockout.AllowedForNewUsers = true;
        options.Lockout.MaxFailedAccessAttempts = 5;
        options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
        options.User.RequireUniqueEmail = true;
        options.SignIn.RequireConfirmedEmail = true;
    })
    .AddUserStore<DapperUserStore>()
    .AddDefaultTokenProviders();
builder.Services.Configure<PasswordHasherOptions>(options =>
{
    options.CompatibilityMode = PasswordHasherCompatibilityMode.IdentityV3;
    options.IterationCount = 210_000;
});

var configuredIdentityEmail = builder.Configuration
    .GetSection(EmailOptions.SectionName)
    .Get<EmailOptions>() ?? new EmailOptions();
if (configuredIdentityEmail.Enabled)
{
    builder.Services.AddSingleton(serviceProvider =>
    {
        var emailOptions = serviceProvider.GetRequiredService<IOptions<EmailOptions>>().Value;
        var credential = serviceProvider.GetRequiredService<TokenCredential>();
        return new EmailClient(new Uri(emailOptions.Endpoint), credential);
    });
    builder.Services.AddSingleton<IIdentityEmailSender, AzureCommunicationIdentityEmailSender>();
}
else
{
    builder.Services.AddSingleton<IIdentityEmailSender, DisabledIdentityEmailSender>();
}
builder.Services.AddScoped<IAuthenticationService, AuthenticationService>();

var authenticationBuilder = builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer()
    .AddCookie(ExternalAuthenticationEndpoints.ExternalCookieScheme, options =>
    {
        options.Cookie.Name = "__Host-fp_external";
        options.Cookie.HttpOnly = true;
        options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.Cookie.Path = "/";
        options.ExpireTimeSpan = TimeSpan.FromMinutes(10);
        options.SlidingExpiration = false;
    });
var entra = builder.Configuration
    .GetSection($"{AuthenticationOptions.SectionName}:External:Entra")
    .Get<EntraAuthenticationOptions>() ?? new EntraAuthenticationOptions();
if (entra.Enabled)
{
    authenticationBuilder.AddOpenIdConnect(
        ExternalAuthenticationEndpoints.EntraScheme,
        options => EntraOpenIdConnectConfiguration.Configure(options, entra));
}
builder.Services
    .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IOptions<AuthenticationOptions>>((options, authenticationOptions) =>
    {
        var jwt = authenticationOptions.Value.Jwt;
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwt.Issuer,
            ValidateAudience = true,
            ValidAudience = jwt.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Convert.FromBase64String(jwt.SigningKey)),
            ValidAlgorithms = [SecurityAlgorithms.HmacSha512],
            ValidateLifetime = true,
            RequireExpirationTime = true,
            RequireSignedTokens = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };
    });
builder.Services
    .AddAuthorizationBuilder()
    .AddPolicy("authenticated-session", policy =>
        policy.RequireAuthenticatedUser().RequireClaim("auth_level", "full", "mfa_setup"))
    .AddPolicy("full-session", policy =>
        policy.RequireAuthenticatedUser().RequireClaim("auth_level", "full"))
    .AddPolicy("admin-mfa", policy =>
        policy.RequireAuthenticatedUser()
            .RequireClaim("auth_level", "full")
            .RequireClaim("amr", "mfa")
            .AddRequirements(new RecentMfaRequirement())
            .RequireRole(PlatformRoles.Admin, PlatformRoles.SuperAdmin));

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("auth-login", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("auth-registration", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("auth-token", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(5),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("auth-refresh", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("organization-write", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("billing-write", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("payment-webhook", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            $"ip:{httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"}",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("network-connect-write", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("matching-run-create", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("organization-funding-read", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("marketplace-read", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("organization-activity-read", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("source-document-create", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("source-document-mutation", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("import-run-create", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 10,
                Window = TimeSpan.FromMinutes(10),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
    options.AddPolicy("semantic-evaluation-create", httpContext =>
        RateLimitPartition.GetFixedWindowLimiter(
            GetRateLimitPartition(httpContext),
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 2,
                Window = TimeSpan.FromHours(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
});

var configuredCorsOrigins = builder.Configuration["ALLOWED_CORS_ORIGINS"];
var configuredFrontendBaseUrl = builder.Configuration["FRONTEND_BASE_URL"];

builder.Services
    .AddOptions<WebOptions>()
    .Bind(builder.Configuration.GetSection(WebOptions.SectionName))
    .Configure(options =>
    {
        if (!string.IsNullOrWhiteSpace(configuredCorsOrigins))
        {
            options.AllowedCorsOrigins = configuredCorsOrigins
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        }

        if (!string.IsNullOrWhiteSpace(configuredFrontendBaseUrl))
        {
            options.FrontendBaseUrl = configuredFrontendBaseUrl;
        }
    })
    .Validate(WebOptions.IsValid, WebOptions.ValidationMessage)
    .ValidateOnStart();

var healthChecks = builder.Services
    .AddHealthChecks()
    .AddCheck(
        "self",
        () => HealthCheckResult.Healthy(),
        tags: ["live", "ready"]);

if (!builder.Environment.IsEnvironment("Testing"))
{
    healthChecks.AddCheck<SqlReadinessHealthCheck>("sql", tags: ["ready"]);
}

var app = builder.Build();
var webOptions = app.Services.GetRequiredService<IOptions<WebOptions>>().Value;

app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<SecurityHeadersMiddleware>();
app.UseSerilogRequestLogging(options =>
{
    options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        diagnosticContext.Set("CorrelationId", httpContext.TraceIdentifier);
});
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors(policy => policy
    .WithOrigins(webOptions.AllowedCorsOrigins)
    .WithMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
    .WithHeaders("Authorization", "Content-Type", "X-Correlation-ID", "Idempotency-Key", "If-Match")
    .WithExposedHeaders("ETag", "X-Correlation-ID")
    .AllowCredentials());

if (!app.Environment.IsDevelopment() && !app.Environment.IsEnvironment("Testing"))
{
    app.UseHttpsRedirection();
}

app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Testing"))
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapGet(
        "/",
        () => Results.Ok(new ApiStatusResponse(
            "FundingPlatform.Api",
            "ok",
            typeof(Program).Assembly.GetName().Version?.ToString() ?? "unknown")))
    .WithName("ApiRoot");

app.MapHealthChecks("/health", new HealthCheckOptions
{
    Predicate = registration => registration.Tags.Contains("live")
});
if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Testing"))
{
    app.MapHealthChecks("/health/ready", new HealthCheckOptions
    {
        Predicate = registration => registration.Tags.Contains("ready")
    });
}
app.MapFundingOpportunityEndpoints();
app.MapOrganizationFundingOpportunityEndpoints();
app.MapFunderEndpoints();
app.MapAdminFundingEditorialEndpoints();
app.MapAdminImportRunEndpoints();
app.MapAdminSourceDocumentEndpoints();
app.MapAdminFundingDuplicateEndpoints();
app.MapAuthenticationEndpoints();
app.MapExternalAuthenticationEndpoints();
app.MapOrganizationEndpoints();
app.MapProjectEndpoints();
app.MapAdminProjectEndpoints();
app.MapPublicProjectEndpoints();
app.MapMarketplaceEndpoints();
app.MapFundingApplicationEndpoints();
app.MapProjectMatchingEndpoints();
app.MapAdminSemanticEvaluationEndpoints();
app.MapAdminAiExplanationEndpoints();
app.MapSavedSearchAlertEndpoints();
app.MapNetworkingEndpoints();
app.MapBillingEndpoints();

static string GetRateLimitPartition(HttpContext context)
{
    var subject = context.User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? context.User.FindFirstValue("sub");
    if (context.User.Identity?.IsAuthenticated == true &&
        Guid.TryParse(subject, out var userPublicId))
    {
        return $"user:{userPublicId:D}";
    }

    return $"ip:{context.Connection.RemoteIpAddress?.ToString() ?? "unknown"}";
}

app.Run();

public partial class Program;
