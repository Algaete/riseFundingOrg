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
}

internal sealed record BootstrapOptions(string Email, string DisplayName);

internal sealed record GrantSuperAdminOptions(string Email);
