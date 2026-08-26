using System.Text;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.FundingSources.Rss;
using FundingPlatform.Infrastructure.Identity;
using FundingPlatform.Infrastructure.Identity.Persistence;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.SourceDocuments;
using FundingPlatform.Infrastructure.Persistence.Sql;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Application.Semantics;
using FundingPlatform.Infrastructure.Persistence.Semantics;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;

LocalEnvironmentLoader.TryLoad();

using var cancellationSource = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellationSource.Cancel();
};

if (args.Length == 0 || args[0] is "--help" or "-h")
{
    PrintUsage();
    return 0;
}

try
{
    if (IsSupportedCommand(args[0]))
    {
        await VerifyDeploymentTargetAsync(cancellationSource.Token);
    }

    if (string.Equals(args[0], "bootstrap-superadmin", StringComparison.OrdinalIgnoreCase))
    {
        return await BootstrapSuperAdminAsync(args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "list-admins", StringComparison.OrdinalIgnoreCase))
    {
        return await ListAdministratorsAsync(args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "grant-superadmin", StringComparison.OrdinalIgnoreCase))
    {
        return await GrantSuperAdminAsync(args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "configure-defender-event-grid-trust", StringComparison.OrdinalIgnoreCase))
    {
        return await ConfigureDefenderEventGridTrustAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "configure-funding-source-policy", StringComparison.OrdinalIgnoreCase))
    {
        return await ConfigureFundingSourcePolicyAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "register-openai-embedding-policy", StringComparison.OrdinalIgnoreCase))
    {
        return await RegisterOpenAiEmbeddingPolicyAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "publish-openai-semantic-configuration", StringComparison.OrdinalIgnoreCase))
    {
        return await PublishOpenAiSemanticConfigurationAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "register-openai-structured-output-policy", StringComparison.OrdinalIgnoreCase))
    {
        return await RegisterOpenAiStructuredOutputPolicyAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    if (string.Equals(args[0], "publish-openai-explanation-configuration", StringComparison.OrdinalIgnoreCase))
    {
        return await PublishOpenAiExplanationConfigurationAsync(
            args.Skip(1).ToArray(), cancellationSource.Token);
    }

    Console.Error.WriteLine("Unknown command. Use --help to list available commands.");
    return 1;
}
catch (OperationCanceledException)
{
    Console.Error.WriteLine("Administration command cancelled.");
    return 130;
}
catch (AuthenticationDataException exception)
{
    Console.Error.WriteLine(
        $"Identity database operation failed: operation={exception.Operation}, " +
        $"sqlError={exception.SqlErrorNumber}.");
    return 4;
}
catch (FundingSourceAcquisitionPolicyDataException exception)
{
    Console.Error.WriteLine(
        $"Funding-source policy database operation failed: operation={ForConsole(exception.Operation)}, " +
        $"sqlError={exception.DatabaseErrorNumber}.");
    return 4;
}
catch (AiProviderGovernanceAdministrationDataException exception)
{
    Console.Error.WriteLine(
        $"AI-governance database operation failed: operation={ForConsole(exception.Operation)}, " +
        $"sqlError={exception.DatabaseErrorNumber}.");
    return 4;
}
catch (MigrationException exception)
{
    Console.Error.WriteLine(
        $"SQL deployment target verification failed: code={ForConsole(exception.Code)}.");
    return 2;
}
catch (InvalidOperationException exception)
{
    Console.Error.WriteLine($"Configuration error: {exception.Message}");
    return 2;
}
catch (ArgumentException exception)
{
    Console.Error.WriteLine($"Invalid arguments: {exception.Message}");
    return 1;
}
catch (Exception)
{
    Console.Error.WriteLine(
        "Administration command failed unexpectedly. No credentials or provider payloads were written to the console.");
    return 5;
}

static async Task<int> BootstrapSuperAdminAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    var options = ParseBootstrapOptions(arguments);
    if (Console.IsInputRedirected)
    {
        throw new InvalidOperationException(
            "Interactive input is required so the password is not passed through arguments or a pipe.");
    }

    var password = ReadHiddenLine("Password: ");
    var confirmation = ReadHiddenLine("Confirm password: ");
    if (!string.Equals(password, confirmation, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Passwords do not match.");
        return 1;
    }

    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var connectionFactory = new SqlConnectionFactory(configuration);
    var passwordHasher = new PasswordHasher<PlatformUser>(Options.Create(new PasswordHasherOptions
    {
        CompatibilityMode = PasswordHasherCompatibilityMode.IdentityV3,
        IterationCount = 210_000
    }));
    var service = new AdminBootstrapService(
        connectionFactory,
        passwordHasher,
        TimeProvider.System);
    var outcome = await service.BootstrapAsync(
        options.Email,
        options.DisplayName,
        password,
        cancellationToken);

    return outcome switch
    {
        AdminBootstrapOutcome.Created => WriteBootstrapResult(
            "SuperAdmin created. MFA setup will be required at first login.", 0),
        AdminBootstrapOutcome.AlreadyConfigured => WriteBootstrapResult(
            "A SuperAdmin is already configured; no changes were made.", 6),
        AdminBootstrapOutcome.EmailAlreadyExists => WriteBootstrapResult(
            "The email already belongs to another account; no changes were made.", 7),
        _ => WriteBootstrapResult("The SuperAdmin role seed is missing.", 8)
    };
}

static bool IsSupportedCommand(string command) => command.ToLowerInvariant() is
    "bootstrap-superadmin" or
    "list-admins" or
    "grant-superadmin" or
    "configure-defender-event-grid-trust" or
    "configure-funding-source-policy" or
    "register-openai-embedding-policy" or
    "publish-openai-semantic-configuration" or
    "register-openai-structured-output-policy" or
    "publish-openai-explanation-configuration";

static async Task VerifyDeploymentTargetAsync(CancellationToken cancellationToken)
{
    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var expectedDatabaseName =
        configuration[MigrationSafety.ExpectedDatabaseConfigurationKey];
    var resolvedDatabaseName =
        MigrationSafety.ResolveExpectedDatabaseName(expectedDatabaseName);
    var verifier = new SqlDeploymentTargetVerifier(
        new SqlConnectionFactory(configuration),
        expectedDatabaseName,
        configuration[MigrationSafety.ExpectedServerConfigurationKey],
        requireExpectedServer:
            !string.Equals(
                resolvedDatabaseName,
                MigrationSafety.ExpectedDatabaseName,
                StringComparison.OrdinalIgnoreCase));
    _ = await verifier.VerifyAsync(cancellationToken);
}

static async Task<int> ListAdministratorsAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (arguments.Length != 0)
    {
        throw new ArgumentException("list-admins does not accept options.");
    }

    var service = CreateGlobalRoleAdministrationService();
    var administrators = await service.ListAdministratorsAsync(cancellationToken);
    if (administrators.Count == 0)
    {
        Console.WriteLine("No Admin or SuperAdmin roles are currently assigned.");
        return 0;
    }

    Console.WriteLine("Global administrators:");
    foreach (var administrator in administrators)
    {
        var mfaState = administrator.TwoFactorEnabled ? "enabled" : "setup-required";
        Console.WriteLine(
            $"- email={ForConsole(administrator.MaskedEmail)}, " +
            $"role={ForConsole(administrator.RoleName)}, " +
            $"status={administrator.Status}, emailConfirmed={administrator.EmailConfirmed}, " +
            $"mfa={mfaState}, grantedAtUtc={administrator.GrantedAtUtc:O}");
    }

    return 0;
}

static async Task<int> GrantSuperAdminAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    var options = ParseGrantSuperAdminOptions(arguments);
    if (Console.IsInputRedirected)
    {
        throw new InvalidOperationException(
            "Interactive confirmation is required for a global role grant.");
    }

    const string expectedConfirmation = "GRANT SUPERADMIN";
    Console.WriteLine(
        "This operation grants full platform administration, revokes the account's existing " +
        "refresh sessions, and requires MFA for administrative access.");
    Console.Write($"Type '{expectedConfirmation}' to continue: ");
    var confirmation = Console.ReadLine();
    if (!string.Equals(confirmation?.Trim(), expectedConfirmation, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }

    var service = CreateGlobalRoleAdministrationService();
    var result = await service.GrantSuperAdminAsync(options.Email, cancellationToken);
    return result.Outcome switch
    {
        GrantSuperAdminOutcome.Granted => WriteGrantResult(
            $"SuperAdmin granted to {ForConsole(result.MaskedEmail)}. Existing refresh sessions " +
            "were revoked; sign in again and complete MFA setup or challenge.", 0),
        GrantSuperAdminOutcome.AlreadyGranted => WriteGrantResult(
            $"{ForConsole(result.MaskedEmail)} already has the SuperAdmin role; no changes were made.", 0),
        GrantSuperAdminOutcome.UserNotFound => WriteGrantResult(
            "No registered account has that email; no changes were made.", 9),
        GrantSuperAdminOutcome.UserNotEligible => WriteGrantResult(
            "The account must be active with a confirmed email; no changes were made.", 10),
        _ => WriteGrantResult("The SuperAdmin role seed is missing; no changes were made.", 8)
    };
}

static GlobalRoleAdministrationService CreateGlobalRoleAdministrationService()
{
    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var connectionFactory = new SqlConnectionFactory(configuration);
    return new GlobalRoleAdministrationService(connectionFactory, TimeProvider.System);
}

static async Task<int> ConfigureDefenderEventGridTrustAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for trust-policy configuration.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--policy-id", "--etag", "--tenant-id",
        "--principal-object-id", "--application-client-id", "--topic-resource-id",
        "--event-subscription-name", "--storage-account-resource-id",
        "--storage-account-host", "--quarantine-container", "--valid-from-utc",
        "--expires-at-utc", "--reason", "--idempotency-key", "--disabled");
    var disabled = values.ContainsKey("--disabled");
    var policyId = OptionalGuid(values, "--policy-id");
    var rowVersion = OptionalRowVersion(values, "--etag");
    if (policyId.HasValue != (rowVersion is { Length: 8 }))
        throw new ArgumentException("--policy-id and --etag must be supplied together for updates.");
    var command = new EventIngressTrustPolicyCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        policyId,
        rowVersion,
        RequiredGuid(values, "--tenant-id"),
        RequiredGuid(values, "--principal-object-id"),
        RequiredGuid(values, "--application-client-id"),
        Required(values, "--topic-resource-id"),
        Required(values, "--event-subscription-name"),
        Required(values, "--storage-account-resource-id"),
        Required(values, "--storage-account-host"),
        Required(values, "--quarantine-container"),
        !disabled,
        RequiredUtc(values, "--valid-from-utc"),
        OptionalUtc(values, "--expires-at-utc"),
        Required(values, "--reason"),
        Required(values, "--idempotency-key"),
        $"admincli-{Guid.NewGuid():N}");

    const string expected = "CONFIGURE DEFENDER TRUST";
    Console.WriteLine(
        "This changes the exact authenticated Event Grid ingress allowlist. " +
        "No Azure resource is created and no credential is stored.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }

    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var repository = new SqlEventIngressTrustPolicyRepository(
        new SqlConnectionFactory(configuration));
    var result = await new EventIngressTrustPolicyAdministrationService(
        repository, TimeProvider.System).UpsertAsync(command, cancellationToken);
    if (!result.Succeeded || result.PolicyId is null || result.RowVersion is not { Length: 8 })
    {
        Console.Error.WriteLine($"Trust policy was not changed: code={ForConsole(result.Code)}.");
        return result.Code is "etag-conflict" or "idempotency-conflict" ? 11 : 12;
    }
    Console.WriteLine(
        $"Trust policy configured: policyId={result.PolicyId:D}, enabled={result.IsEnabled}, " +
        $"etag={Convert.ToBase64String(result.RowVersion)}, replay={result.WasReplay}.");
    return 0;
}

static async Task<int> ConfigureFundingSourcePolicyAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for funding-source policy configuration.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--provider-code", "--base-url", "--license-name",
        "--license-url", "--license-reviewed-at-utc", "--license-expires-at-utc",
        "--robots-url", "--robots-policy", "--robots-policy-version",
        "--robots-reviewed-at-utc", "--robots-expires-at-utc", "--allowed-hosts",
        "--rate-per-minute", "--maximum-response-bytes", "--retention-days",
        "--schedule-interval-seconds", "--idempotency-key", "--enabled",
        "--compliance-approved");
    var baseUrl = Required(values, "--base-url");
    var licenseUrl = Required(values, "--license-url");
    var robotsUrl = Required(values, "--robots-url");
    var command = new FundingSourceAcquisitionPolicyCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        Required(values, "--provider-code"),
        baseUrl,
        Required(values, "--license-name"),
        licenseUrl,
        RequiredUtc(values, "--license-reviewed-at-utc"),
        OptionalUtc(values, "--license-expires-at-utc"),
        Required(values, "--robots-policy"),
        RequiredInt(values, "--robots-policy-version"),
        RequiredUtc(values, "--robots-reviewed-at-utc"),
        RequiredUtc(values, "--robots-expires-at-utc"),
        Required(values, "--allowed-hosts")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
        [
            new FundingSourceAcquisitionEndpoint(
                FundingSourceAcquisitionEndpointKind.Acquisition, baseUrl),
            new FundingSourceAcquisitionEndpoint(
                FundingSourceAcquisitionEndpointKind.License, licenseUrl),
            new FundingSourceAcquisitionEndpoint(
                FundingSourceAcquisitionEndpointKind.Robots, robotsUrl)
        ],
        RequiredInt(values, "--rate-per-minute"),
        RequiredInt(values, "--maximum-response-bytes"),
        RequiredInt16(values, "--retention-days"),
        OptionalInt(values, "--schedule-interval-seconds"),
        values.ContainsKey("--enabled"),
        values.ContainsKey("--compliance-approved"),
        Required(values, "--idempotency-key"),
        $"admincli-{Guid.NewGuid():N}");

    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var rssOptions = configuration.GetSection(OfficialRssOptions.SectionName)
        .Get<OfficialRssOptions>() ?? new OfficialRssOptions();
    OfficialRssPolicyPreflight.ValidateEnabledPolicy(command, rssOptions);

    const string expected = "CONFIGURE FUNDING SOURCE POLICY";
    Console.WriteLine(
        "This creates an immutable, audited acquisition policy version for one fixed " +
        "official source. It does not fetch data or store a credential.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }

    var repository = new SqlFundingSourceAcquisitionPolicyRepository(
        new SqlConnectionFactory(configuration));
    var result = await new FundingSourceAcquisitionPolicyAdministrationService(
        repository, TimeProvider.System).UpsertAsync(command, cancellationToken);
    if (!result.Succeeded || result.FundingSourceId is null || result.PolicyId is null ||
        result.PolicyVersion is null or < 1 ||
        result.AcquisitionPolicyFingerprint is not { Length: 32 })
    {
        Console.Error.WriteLine(
            $"Funding-source policy was not changed: code={ForConsole(result.Code)}.");
        return 12;
    }
    Console.WriteLine(
        $"Funding-source policy configured: sourceId={result.FundingSourceId}, " +
        $"policyId={result.PolicyId:D}, version={result.PolicyVersion}, " +
        $"fingerprint={Convert.ToHexString(result.AcquisitionPolicyFingerprint)}, " +
        $"enabled={result.IsEnabled}, replay={result.WasReplay}.");
    return 0;
}

static async Task<int> RegisterOpenAiEmbeddingPolicyAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for AI provider governance.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--code", "--version", "--model",
        "--endpoint-origin", "--data-residency", "--dpa-reference-sha256",
        "--terms-snapshot-sha256", "--input-token-cost-usd-per-million",
        "--approved-at-utc", "--expires-at-utc", "--idempotency-key");
    var command = new AiEmbeddingProviderPolicyCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        Required(values, "--code"),
        RequiredInt(values, "--version"),
        Required(values, "--model"),
        Required(values, "--endpoint-origin"),
        Required(values, "--data-residency"),
        RequiredSha256(values, "--dpa-reference-sha256"),
        RequiredSha256(values, "--terms-snapshot-sha256"),
        RequiredDecimal(values, "--input-token-cost-usd-per-million"),
        RequiredUtc(values, "--approved-at-utc"),
        RequiredUtc(values, "--expires-at-utc"),
        Required(values, "--idempotency-key"));

    const string expected = "REGISTER OPENAI EMBEDDING POLICY";
    Console.WriteLine(
        "This registers an immutable OpenAI embedding governance decision. It stores " +
        "document hashes and limits only; it stores no API key and makes no provider call.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }

    var service = CreateAiProviderGovernanceService();
    var result = await service.RegisterEmbeddingPolicyAsync(command, cancellationToken);
    if (!result.Succeeded || result.PolicyPublicId == Guid.Empty ||
        result.PolicyFingerprint is not { Length: 32 })
    {
        Console.Error.WriteLine($"AI provider policy was not registered: code={ForConsole(result.Code)}.");
        return 12;
    }
    Console.WriteLine(
        $"AI provider policy registered: policyId={result.PolicyPublicId:D}, " +
        $"version={ForConsole(result.PolicyVersion)}, provider={ForConsole(result.ProviderCode)}, " +
        $"model={ForConsole(result.ModelCode)}, residency={ForConsole(result.DataResidencyCode)}, " +
        $"fingerprint={Convert.ToHexString(result.PolicyFingerprint)}, " +
        $"expiresAtUtc={result.ExpiresAtUtc:O}, replay={result.WasReplay}.");
    return 0;
}

static async Task<int> PublishOpenAiSemanticConfigurationAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for semantic configuration publication.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--provider-policy-id", "--code", "--version",
        "--maximum-batch-size", "--maximum-cost-usd-per-embedding",
        "--monthly-budget-usd", "--idempotency-key");
    var batchSize = RequiredInt(values, "--maximum-batch-size");
    if (batchSize is < byte.MinValue or > byte.MaxValue)
        throw new ArgumentException("--maximum-batch-size is outside the supported range.");
    var command = new OpenAiSemanticConfigurationCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        RequiredGuid(values, "--provider-policy-id"),
        Required(values, "--code"),
        RequiredInt(values, "--version"),
        (byte)batchSize,
        RequiredDecimal(values, "--maximum-cost-usd-per-embedding"),
        RequiredDecimal(values, "--monthly-budget-usd"),
        Required(values, "--idempotency-key"));

    const string expected = "PUBLISH OPENAI SEMANTIC CONFIGURATION";
    Console.WriteLine(
        "This replaces the active semantic configuration after all existing work drains. " +
        "It does not enable the worker, run an evaluation, promote semantic results, or call OpenAI.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }

    var service = CreateAiProviderGovernanceService();
    var result = await service.PublishOpenAiConfigurationAsync(command, cancellationToken);
    if (!result.Succeeded || result.ConfigurationPublicId == Guid.Empty ||
        result.ProviderPolicyFingerprint is not { Length: 32 })
    {
        Console.Error.WriteLine(
            $"Semantic configuration was not published: code={ForConsole(result.Code)}.");
        return 12;
    }
    Console.WriteLine(
        $"Semantic configuration published: configurationId={result.ConfigurationPublicId:D}, " +
        $"version={ForConsole(result.ConfigurationVersion)}, " +
        $"policyId={result.ProviderPolicyPublicId:D}, model={ForConsole(result.ModelCode)}, " +
        $"monthlyBudgetUsd={result.MonthlyBudgetUsd}, active={result.IsActive}, " +
        $"replay={result.WasReplay}.");
    return 0;
}

static AiProviderGovernanceAdministrationService CreateAiProviderGovernanceService()
{
    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var repository = new SqlAiProviderGovernanceAdministrationRepository(
        new SqlConnectionFactory(configuration));
    return new AiProviderGovernanceAdministrationService(repository, TimeProvider.System);
}

static async Task<int> RegisterOpenAiStructuredOutputPolicyAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for AI provider governance.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--code", "--version", "--endpoint-origin",
        "--data-residency", "--dpa-reference-sha256", "--terms-snapshot-sha256",
        "--input-token-cost-usd-per-million", "--output-token-cost-usd-per-million",
        "--approved-at-utc", "--expires-at-utc", "--idempotency-key");
    var command = new AiStructuredOutputProviderPolicyCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        Required(values, "--code"),
        RequiredInt(values, "--version"),
        Required(values, "--endpoint-origin"),
        Required(values, "--data-residency"),
        RequiredSha256(values, "--dpa-reference-sha256"),
        RequiredSha256(values, "--terms-snapshot-sha256"),
        RequiredDecimal(values, "--input-token-cost-usd-per-million"),
        RequiredDecimal(values, "--output-token-cost-usd-per-million"),
        RequiredUtc(values, "--approved-at-utc"),
        RequiredUtc(values, "--expires-at-utc"),
        Required(values, "--idempotency-key"));
    const string expected = "REGISTER OPENAI STRUCTURED OUTPUT POLICY";
    Console.WriteLine(
        "This registers an immutable Zero Data Retention governance decision for " +
        "gpt-5.6-sol Structured Outputs. It stores hashes and limits only; it stores no " +
        "API key and makes no provider call.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }
    var result = await CreateAiProviderGovernanceService()
        .RegisterStructuredOutputPolicyAsync(command, cancellationToken);
    if (!result.Succeeded || result.PolicyPublicId == Guid.Empty ||
        result.PolicyFingerprint is not { Length: 32 })
    {
        Console.Error.WriteLine(
            $"Structured Outputs policy was not registered: code={ForConsole(result.Code)}.");
        return 12;
    }
    Console.WriteLine(
        $"Structured Outputs policy registered: policyId={result.PolicyPublicId:D}, " +
        $"version={ForConsole(result.PolicyVersion)}, model={ForConsole(result.ModelCode)}, " +
        $"residency={ForConsole(result.DataResidencyCode)}, " +
        $"fingerprint={Convert.ToHexString(result.PolicyFingerprint)}, " +
        $"expiresAtUtc={result.ExpiresAtUtc:O}, replay={result.WasReplay}.");
    return 0;
}

static async Task<int> PublishOpenAiExplanationConfigurationAsync(
    string[] arguments,
    CancellationToken cancellationToken)
{
    if (Console.IsInputRedirected || Console.IsOutputRedirected)
        throw new InvalidOperationException(
            "An interactive terminal is required for explanation configuration publication.");
    var values = ParseNamedOptions(arguments,
        "--superadmin-user-id", "--provider-policy-id", "--code", "--version",
        "--maximum-output-tokens", "--maximum-cost-usd-per-result",
        "--monthly-budget-usd", "--idempotency-key");
    var outputTokens = RequiredInt(values, "--maximum-output-tokens");
    if (outputTokens is < short.MinValue or > short.MaxValue)
        throw new ArgumentException("--maximum-output-tokens is outside the supported range.");
    var command = new OpenAiExplanationConfigurationCommand(
        RequiredGuid(values, "--superadmin-user-id"),
        RequiredGuid(values, "--provider-policy-id"),
        Required(values, "--code"),
        RequiredInt(values, "--version"),
        (short)outputTokens,
        RequiredDecimal(values, "--maximum-cost-usd-per-result"),
        RequiredDecimal(values, "--monthly-budget-usd"),
        Required(values, "--idempotency-key"));
    const string expected = "PUBLISH OPENAI EXPLANATION CONFIGURATION";
    Console.WriteLine(
        "This publishes an immutable admin-only shadow configuration. It does not enable " +
        "the worker, create a run, call OpenAI, or change 9A/9B-A results.");
    Console.Write($"Type '{expected}' to continue: ");
    if (!string.Equals(Console.ReadLine()?.Trim(), expected, StringComparison.Ordinal))
    {
        Console.Error.WriteLine("Confirmation did not match; no changes were made.");
        return 1;
    }
    var result = await CreateAiProviderGovernanceService()
        .PublishOpenAiExplanationConfigurationAsync(command, cancellationToken);
    if (!result.Succeeded || result.ConfigurationPublicId == Guid.Empty ||
        result.PromptFingerprint is not { Length: 32 } ||
        result.ResponseSchemaFingerprint is not { Length: 32 })
    {
        Console.Error.WriteLine(
            $"Explanation configuration was not published: code={ForConsole(result.Code)}.");
        return 12;
    }
    Console.WriteLine(
        $"Explanation configuration published: configurationId={result.ConfigurationPublicId:D}, " +
        $"version={ForConsole(result.ConfigurationVersion)}, " +
        $"policyId={result.ProviderPolicyPublicId:D}, model={ForConsole(result.ModelCode)}, " +
        $"maximumOutputTokens={result.MaximumOutputTokens}, " +
        $"monthlyBudgetUsd={result.MonthlyBudgetUsd}, active={result.IsActive}, " +
        $"replay={result.WasReplay}.");
    return 0;
}

static Dictionary<string, string?> ParseNamedOptions(
    string[] arguments,
    params string[] allowedOptions)
{
    var allowed = allowedOptions.ToHashSet(StringComparer.Ordinal);
    var values = new Dictionary<string, string?>(StringComparer.Ordinal);
    for (var index = 0; index < arguments.Length; index++)
    {
        var option = arguments[index];
        if (!allowed.Contains(option) || !values.TryAdd(option, null))
            throw new ArgumentException($"Unknown or repeated option '{option}'.");
        if (option is "--disabled" or "--enabled" or "--compliance-approved") continue;
        values[option] = RequireValue(arguments, ref index, option);
    }
    return values;
}

static string Required(IReadOnlyDictionary<string, string?> values, string option) =>
    values.TryGetValue(option, out var value) && !string.IsNullOrWhiteSpace(value)
        ? value.Trim()
        : throw new ArgumentException($"{option} is required.");

static Guid RequiredGuid(IReadOnlyDictionary<string, string?> values, string option) =>
    Guid.TryParseExact(Required(values, option), "D", out var value) && value != Guid.Empty
        ? value
        : throw new ArgumentException($"{option} must be a canonical non-empty GUID.");

static Guid? OptionalGuid(IReadOnlyDictionary<string, string?> values, string option)
{
    if (!values.ContainsKey(option)) return null;
    return RequiredGuid(values, option);
}

static DateTimeOffset RequiredUtc(
    IReadOnlyDictionary<string, string?> values,
    string option) => ParseUtc(Required(values, option), option);

static DateTimeOffset? OptionalUtc(
    IReadOnlyDictionary<string, string?> values,
    string option) => values.TryGetValue(option, out var value)
        ? ParseUtc(value!, option)
        : null;

static DateTimeOffset ParseUtc(string value, string option) =>
    DateTimeOffset.TryParseExact(value, "O", System.Globalization.CultureInfo.InvariantCulture,
        System.Globalization.DateTimeStyles.None, out var parsed) && parsed.Offset == TimeSpan.Zero
        ? parsed
        : throw new ArgumentException($"{option} must use the UTC round-trip format, ending in +00:00.");

static int RequiredInt(IReadOnlyDictionary<string, string?> values, string option) =>
    int.TryParse(Required(values, option),
        System.Globalization.NumberStyles.None,
        System.Globalization.CultureInfo.InvariantCulture,
        out var parsed)
        ? parsed
        : throw new ArgumentException($"{option} must be an integer.");

static short RequiredInt16(IReadOnlyDictionary<string, string?> values, string option)
{
    var parsed = RequiredInt(values, option);
    return parsed is >= short.MinValue and <= short.MaxValue
        ? (short)parsed
        : throw new ArgumentException($"{option} is outside the supported range.");
}

static int? OptionalInt(
    IReadOnlyDictionary<string, string?> values,
    string option) => values.ContainsKey(option) ? RequiredInt(values, option) : null;

static decimal RequiredDecimal(
    IReadOnlyDictionary<string, string?> values,
    string option) => decimal.TryParse(
        Required(values, option),
        System.Globalization.NumberStyles.AllowDecimalPoint,
        System.Globalization.CultureInfo.InvariantCulture,
        out var parsed)
        ? parsed
        : throw new ArgumentException($"{option} must be a non-exponential decimal using '.'.");

static byte[] RequiredSha256(
    IReadOnlyDictionary<string, string?> values,
    string option)
{
    var text = Required(values, option);
    if (text.Length != 64 || !text.All(Uri.IsHexDigit))
        throw new ArgumentException($"{option} must contain exactly 64 hexadecimal characters.");
    return Convert.FromHexString(text);
}

static byte[]? OptionalRowVersion(
    IReadOnlyDictionary<string, string?> values,
    string option)
{
    if (!values.ContainsKey(option)) return null;
    var text = Required(values, option).Trim('"');
    try
    {
        var bytes = Convert.FromBase64String(text);
        return bytes.Length == 8
            ? bytes
            : throw new ArgumentException($"{option} must contain an eight-byte ETag.");
    }
    catch (FormatException)
    {
        throw new ArgumentException($"{option} must be a base64 ETag.");
    }
}

static GrantSuperAdminOptions ParseGrantSuperAdminOptions(string[] arguments)
{
    string? email = null;
    for (var index = 0; index < arguments.Length; index++)
    {
        var argument = arguments[index];
        if (argument == "--email")
        {
            if (email is not null)
            {
                throw new ArgumentException("--email can only be specified once.");
            }

            email = RequireValue(arguments, ref index, argument);
        }
        else
        {
            throw new ArgumentException($"Unknown option '{argument}'.");
        }
    }

    if (string.IsNullOrWhiteSpace(email))
    {
        throw new ArgumentException("--email is required.");
    }

    return new GrantSuperAdminOptions(email);
}

static BootstrapOptions ParseBootstrapOptions(string[] arguments)
{
    string? email = null;
    string? displayName = null;
    for (var index = 0; index < arguments.Length; index++)
    {
        var argument = arguments[index];
        if (argument == "--email")
        {
            email = RequireValue(arguments, ref index, argument);
        }
        else if (argument == "--display-name")
        {
            displayName = RequireValue(arguments, ref index, argument);
        }
        else
        {
            throw new ArgumentException($"Unknown option '{argument}'.");
        }
    }

    if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(displayName))
    {
        throw new ArgumentException("--email and --display-name are required.");
    }

    return new BootstrapOptions(email, displayName);
}

static string ReadHiddenLine(string prompt)
{
    Console.Write(prompt);
    var value = new StringBuilder();
    while (true)
    {
        var key = Console.ReadKey(intercept: true);
        if (key.Key == ConsoleKey.Enter)
        {
            Console.WriteLine();
            return value.ToString();
        }

        if (key.Key == ConsoleKey.Backspace)
        {
            if (value.Length > 0) value.Length--;
            continue;
        }

        if (!char.IsControl(key.KeyChar) && value.Length < 128)
        {
            value.Append(key.KeyChar);
        }
    }
}

static int WriteBootstrapResult(string message, int exitCode)
{
    var writer = exitCode == 0 ? Console.Out : Console.Error;
    writer.WriteLine(message);
    return exitCode;
}

static int WriteGrantResult(string message, int exitCode)
{
    var writer = exitCode == 0 ? Console.Out : Console.Error;
    writer.WriteLine(message);
    return exitCode;
}

static string ForConsole(string? value)
{
    if (string.IsNullOrEmpty(value))
    {
        return "(not available)";
    }

    return string.Concat(value.Select(character => char.IsControl(character) ? ' ' : character));
}

static string RequireValue(string[] arguments, ref int index, string option)
{
    if (index + 1 >= arguments.Length)
    {
        throw new ArgumentException($"Option '{option}' requires a value.");
    }

    index++;
    return arguments[index];
}

static void PrintUsage()
{
    Console.WriteLine("FundingPlatform administration commands");
    Console.WriteLine();
    Console.WriteLine("  bootstrap-superadmin --email <address> --display-name <name>");
    Console.WriteLine("  list-admins");
    Console.WriteLine("  grant-superadmin --email <existing-account-address>");
    Console.WriteLine(
        "  configure-defender-event-grid-trust --superadmin-user-id <guid> " +
        "--tenant-id <guid> --principal-object-id <guid> --application-client-id <guid> " +
        "--topic-resource-id <azure-resource-id> --event-subscription-name <name> " +
        "--storage-account-resource-id <azure-resource-id> --storage-account-host <host> " +
        "--quarantine-container <name> --valid-from-utc <round-trip-utc> " +
        "--reason <text> --idempotency-key <key> [--expires-at-utc <utc>] " +
        "[--policy-id <guid> --etag <base64>] [--disabled]");
    Console.WriteLine(
        "  configure-funding-source-policy --superadmin-user-id <guid> " +
        "--provider-code official-rss --base-url <exact-feed-https-url> " +
        "--license-name <name> --license-url <https-url> " +
        "--license-reviewed-at-utc <utc> --robots-url <exact-https-url> " +
        "--robots-policy enforce --robots-policy-version <n> " +
        "--robots-reviewed-at-utc <utc> --robots-expires-at-utc <utc> " +
        "--allowed-hosts <comma-separated-hosts> --rate-per-minute <n> " +
        "--maximum-response-bytes <n> --retention-days <n> " +
        "--idempotency-key <key> [--license-expires-at-utc <utc>] " +
        "[--schedule-interval-seconds <n>] [--enabled] [--compliance-approved]");
    Console.WriteLine(
        "  register-openai-embedding-policy --superadmin-user-id <guid> --code <code> " +
        "--version <n> --model <text-embedding-3-small|text-embedding-3-large> " +
        "--endpoint-origin <official-origin> --data-residency <region> " +
        "--dpa-reference-sha256 <sha256> --terms-snapshot-sha256 <sha256> " +
        "--input-token-cost-usd-per-million <decimal> --approved-at-utc <utc> " +
        "--expires-at-utc <utc> --idempotency-key <key>");
    Console.WriteLine(
        "  publish-openai-semantic-configuration --superadmin-user-id <guid> " +
        "--provider-policy-id <guid> --code <code> --version <n> " +
        "--maximum-batch-size <1..64> --maximum-cost-usd-per-embedding <decimal> " +
        "--monthly-budget-usd <decimal> --idempotency-key <key>");
    Console.WriteLine(
        "  register-openai-structured-output-policy --superadmin-user-id <guid> " +
        "--code <code> --version <n> --endpoint-origin <official-origin> " +
        "--data-residency <region> --dpa-reference-sha256 <sha256> " +
        "--terms-snapshot-sha256 <sha256> " +
        "--input-token-cost-usd-per-million <decimal> " +
        "--output-token-cost-usd-per-million <decimal> --approved-at-utc <utc> " +
        "--expires-at-utc <utc> --idempotency-key <key>");
    Console.WriteLine(
        "  publish-openai-explanation-configuration --superadmin-user-id <guid> " +
        "--provider-policy-id <guid> --code <code> --version <n> " +
        "--maximum-output-tokens <128..1024> " +
        "--maximum-cost-usd-per-result <decimal> --monthly-budget-usd <decimal> " +
        "--idempotency-key <key>");
}

internal sealed record BootstrapOptions(string Email, string DisplayName);

internal sealed record GrantSuperAdminOptions(string Email);
