using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

LocalEnvironmentLoader.TryLoad();

if (args.Length == 0 || !IsSupportedCommand(args[0]) ||
    (!IsRuntimeIdentityCommand(args[0]) && args.Length != 1))
{
    PrintUsage();
    return 64;
}

try
{
    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var connectionFactory = new SqlConnectionFactory(configuration);
    var expectedDatabaseName =
        configuration[MigrationSafety.ExpectedDatabaseConfigurationKey];
    var expectedServerFqdn =
        configuration[MigrationSafety.ExpectedServerConfigurationKey];

    if (args[0] == "--check-connection")
    {
        return await CheckConnectionAsync(
            connectionFactory,
            expectedDatabaseName,
            expectedServerFqdn);
    }

    var solutionRoot = SolutionRootLocator.Find();
    var migrations = SqlScriptCatalog.DiscoverMigrations(solutionRoot);
    IReadOnlyList<SqlScript> provisioning = [];
    if (args[0] is "--validate" or "--preflight" or "--provision-full-text")
    {
        provisioning = SqlScriptCatalog.DiscoverProvisioning(solutionRoot);
        EnsureExpectedFullTextProvisioning(provisioning);
    }
    var runner = new DatabaseMigrationRunner(
        connectionFactory,
        expectedDatabaseName,
        expectedServerFqdn);

    switch (args[0])
    {
        case "--status":
            return await ShowStatusAsync(runner, migrations);

        case "--validate":
            {
                var result = await runner.ValidateAsync(migrations);
                var fullText = await runner.GetFullTextProvisioningStatusAsync(migrations);
                Console.WriteLine(
                    $"Validación correcta: {result.ExecutedScripts} migración(es), " +
                    $"{result.ExecutedBatches} lote(s). Todos los cambios fueron revertidos.");
                Console.WriteLine(
                    $"Provisioning Full-Text descubierto: {provisioning.Count} script(s); " +
                    $"estado no mutado: {FormatFullTextState(fullText.State)}.");
                return 0;
            }

        case "--apply":
            {
                var result = await runner.ApplyAsync(migrations);
                Console.WriteLine(
                    $"Aplicación correcta: {result.ExecutedScripts} migración(es), " +
                    $"{result.ExecutedBatches} lote(s).");
                return 0;
            }

        case "--preflight":
            {
                var tests = SqlScriptCatalog.DiscoverTests(solutionRoot);
                var result = await runner.PreflightAsync(migrations, tests);
                Console.WriteLine(
                    $"Preflight correcto: {result.Migrations.ExecutedScripts} migración(es), " +
                    $"{result.Migrations.ExecutedBatches} lote(s); " +
                    $"{result.Tests.ExecutedScripts} prueba(s), " +
                    $"{result.Tests.ExecutedBatches} lote(s). " +
                    "Todos los cambios fueron revertidos.");
                return 0;
            }

        case "--test":
            {
                var tests = SqlScriptCatalog.DiscoverTests(solutionRoot);
                var result = await runner.TestAsync(migrations, tests);
                Console.WriteLine(
                    $"Pruebas SQL correctas: {result.ExecutedScripts} script(s), " +
                    $"{result.ExecutedBatches} lote(s). Todos los cambios fueron revertidos.");
                return 0;
            }

        case "--provision-full-text":
            {
                var result = await runner.ProvisionFullTextAsync(migrations, provisioning);
                var fullText = await runner.GetFullTextProvisioningStatusAsync(migrations);
                var accepted = fullText.State is "ready" or "populating";
                var message =
                    $"Provisioning Full-Text ejecutado: {result.ExecutedScripts} script(s), " +
                    $"{result.ExecutedBatches} lote(s). Estado: " +
                    $"{FormatFullTextState(fullText.State)}.";
                if (accepted) Console.WriteLine(message);
                else Console.Error.WriteLine(message);
                return accepted ? 0 : 3;
            }

        case "--provision-runtime-identities":
        case "--verify-runtime-identities":
            {
                var plan = ParseRuntimeIdentityPlan(args.Skip(1).ToArray());
                var provisioner = new RuntimeDatabaseIdentityProvisioner(
                    connectionFactory,
                    expectedDatabaseName,
                    expectedServerFqdn);
                var result = args[0] == "--provision-runtime-identities"
                    ? await provisioner.ProvisionAndVerifyAsync(migrations, plan)
                    : await provisioner.VerifyAsync(migrations, plan);
                Console.WriteLine(
                    $"Identidades runtime verificadas en " +
                    $"{provisioner.ExpectedServerFqdn}/{provisioner.ExpectedDatabaseName}: " +
                    $"usuarios={result.VerifiedUsers}, " +
                    $"ausencias={result.VerifiedAbsentIdentities}, " +
                    $"creados={result.CreatedUsers}, " +
                    $"membresías agregadas={result.AddedMemberships}.");
                return 0;
            }
    }
}
catch (MigrationException exception)
{
    var item = string.IsNullOrWhiteSpace(exception.Item)
        ? string.Empty
        : $" Elemento: {exception.Item}.";
    var sqlNumber = exception.DatabaseErrorNumber.HasValue
        ? $" Número SQL: {exception.DatabaseErrorNumber.Value}."
        : string.Empty;
    var sqlLine = exception.InnerException is SqlException sqlException
        ? sqlException.Errors
            .Cast<SqlError>()
            .Where(error => error.LineNumber > 0)
            .Select(error => $" Línea SQL: {error.LineNumber}.")
            .FirstOrDefault() ?? string.Empty
        : string.Empty;
    Console.Error.WriteLine(
        $"Operación de migración rechazada. Código: {exception.Code}.{item}{sqlNumber}{sqlLine}");
    return 3;
}
catch (SqlException exception)
{
    Console.Error.WriteLine(
        $"La operación SQL falló de forma sanitizada. Número SQL: {exception.Number}.");
    return 1;
}
catch (InvalidOperationException)
{
    Console.Error.WriteLine(
        "No se pudo configurar la conexión Azure SQL. Define " +
        "'ConnectionStrings:DefaultConnection' o su variable de entorno compatible.");
    return 2;
}
catch (ArgumentException)
{
    Console.Error.WriteLine("Los argumentos de la operación no son válidos.");
    PrintUsage();
    return 64;
}
catch (OperationCanceledException)
{
    Console.Error.WriteLine("La operación fue cancelada.");
    return 130;
}
catch (Exception)
{
    Console.Error.WriteLine("La operación falló con un error inesperado y sanitizado.");
    return 1;
}

return 1;

static bool IsSupportedCommand(string command) =>
    command is "--check-connection" or "--status" or "--validate" or "--preflight"
        or "--apply" or "--test"
        or "--provision-full-text" or "--provision-runtime-identities"
        or "--verify-runtime-identities";

static bool IsRuntimeIdentityCommand(string command) =>
    command is "--provision-runtime-identities" or "--verify-runtime-identities";

static void PrintUsage()
{
    Console.Error.WriteLine(
        "Uso: FundingPlatform.DatabaseMigrator " +
        "[--check-connection|--status|--validate|--preflight|--apply|--test|" +
        "--provision-full-text]");
    Console.Error.WriteLine(
        "  FundingPlatform.DatabaseMigrator " +
        "[--provision-runtime-identities|--verify-runtime-identities] " +
        "--api-user <name> --api-client-id <guid> " +
        "--general-worker-user <name> --general-worker-client-id <guid> " +
        "--extraction-consumer-user <name> --extraction-consumer-client-id <guid> " +
        "--extraction-host-user <name> --extraction-host-client-id <guid> " +
        "--extraction-sender-user <name> --extraction-sender-client-id <guid>");
}

static void EnsureExpectedFullTextProvisioning(IReadOnlyList<SqlScript> scripts)
{
    if (scripts.Count != 1 || scripts[0].Sequence != 1 ||
        !string.Equals(
            scripts[0].Name,
            "funding_opportunity_full_text",
            StringComparison.Ordinal))
    {
        throw new MigrationException("full_text_provisioning_manifest_invalid");
    }
}

static async Task<int> CheckConnectionAsync(
    ISqlConnectionFactory connectionFactory,
    string? expectedDatabaseName,
    string? expectedServerFqdn)
{
    var targetVerifier = new SqlDeploymentTargetVerifier(
        connectionFactory,
        expectedDatabaseName,
        expectedServerFqdn,
        requireExpectedServer:
            !string.Equals(
                MigrationSafety.ResolveExpectedDatabaseName(expectedDatabaseName),
                MigrationSafety.ExpectedDatabaseName,
                StringComparison.OrdinalIgnoreCase));
    var target = await targetVerifier.VerifyAsync();
    var result = await new SqlConnectionVerifier(connectionFactory).CheckAsync();
    if (result.Succeeded)
    {
        Console.WriteLine(
            $"Conexión SQL verificada con SELECT 1: " +
            $"{target.ConfiguredServerFqdn}/{target.DatabaseName}.");
        return 0;
    }

    var sqlNumber = result.SqlErrorNumber is null
        ? string.Empty
        : $" Número de error SQL: {result.SqlErrorNumber.Value}.";
    Console.Error.WriteLine(
        $"Falló la verificación SELECT 1 en Azure SQL. Código: {result.Code}.{sqlNumber}");
    return 1;
}

static RuntimeDatabaseIdentityPlan ParseRuntimeIdentityPlan(string[] arguments)
{
    string[] allowedOptions =
    [
        "--api-user",
        "--api-client-id",
        "--general-worker-user",
        "--general-worker-client-id",
        "--extraction-consumer-user",
        "--extraction-consumer-client-id",
        "--extraction-host-user",
        "--extraction-host-client-id",
        "--extraction-sender-user",
        "--extraction-sender-client-id"
    ];
    var allowed = allowedOptions.ToHashSet(StringComparer.Ordinal);
    var values = new Dictionary<string, string>(StringComparer.Ordinal);
    for (var index = 0; index < arguments.Length; index++)
    {
        var option = arguments[index];
        if (!allowed.Contains(option) || !values.TryAdd(option, string.Empty) ||
            index + 1 >= arguments.Length || arguments[index + 1].StartsWith("--", StringComparison.Ordinal))
        {
            throw new ArgumentException("invalid_runtime_identity_option");
        }
        values[option] = arguments[++index];
    }

    if (values.Count != allowedOptions.Length)
    {
        throw new ArgumentException("missing_runtime_identity_option");
    }

    string Required(string option) =>
        !string.IsNullOrWhiteSpace(values[option])
            ? values[option]
            : throw new ArgumentException("empty_runtime_identity_option");
    Guid RequiredClientId(string option) =>
        Guid.TryParseExact(Required(option), "D", out var value) && value != Guid.Empty
            ? value
            : throw new ArgumentException("invalid_runtime_identity_client_id");

    return RuntimeDatabaseIdentityPlan.Create(
        Required("--api-user"),
        RequiredClientId("--api-client-id"),
        Required("--general-worker-user"),
        RequiredClientId("--general-worker-client-id"),
        Required("--extraction-consumer-user"),
        RequiredClientId("--extraction-consumer-client-id"),
        Required("--extraction-host-user"),
        RequiredClientId("--extraction-host-client-id"),
        Required("--extraction-sender-user"),
        RequiredClientId("--extraction-sender-client-id"));
}

static async Task<int> ShowStatusAsync(
    DatabaseMigrationRunner runner,
    IReadOnlyList<SqlScript> migrations)
{
    var status = await runner.GetStatusAsync(migrations);
    var fullText = await runner.GetFullTextProvisioningStatusAsync(migrations);
    Console.WriteLine($"Base objetivo: {runner.ExpectedDatabaseName}/verificada");
    Console.WriteLine($"Historial: {(status.HistoryTableExists ? "presente" : "ausente")}");
    var recordedMigrations = status.Migrations.Count(item => item.State != MigrationState.Pending);
    Console.WriteLine($"Migraciones registradas: {recordedMigrations}");
    Console.WriteLine($"Migraciones locales: {status.Migrations.Count}");
    foreach (var migration in status.Migrations)
    {
        Console.WriteLine(
            $"  {migration.Version:D3} {migration.Name} [{FormatState(migration.State)}]");
    }

    Console.WriteLine($"Objetos FundingPlatform_: {status.Objects.Count}");
    foreach (var item in status.Objects)
    {
        Console.WriteLine($"  {item.Type} {item.Name}");
    }
    Console.WriteLine($"Full-Text 8A: {FormatFullTextState(fullText.State)}");

    var acceptedFullTextState = fullText.State is
        "ready" or "populating" or "not-provisioned" or "unavailable" or "migration-pending";
    return status.Migrations.Any(item =>
        item.State is MigrationState.ChecksumChanged or MigrationState.MissingLocalScript)
        || !acceptedFullTextState
        ? 3
        : 0;
}

static string FormatState(MigrationState state) => state switch
{
    MigrationState.Pending => "pendiente",
    MigrationState.Applied => "aplicada",
    MigrationState.ChecksumChanged => "checksum-cambiado",
    MigrationState.MissingLocalScript => "script-local-ausente",
    _ => "desconocido"
};

static string FormatFullTextState(string state) => state switch
{
    "ready" => "listo",
    "populating" => "poblando",
    "not-provisioned" => "no aprovisionado (búsqueda literal de respaldo)",
    "unavailable" => "no disponible (búsqueda literal de respaldo)",
    "migration-pending" => "migración 018 pendiente",
    "migration-drift" => "checksum de migración 018 inconsistente",
    "drift" => "configuración incompatible",
    "population-failed" => "población fallida",
    _ => "desconocido"
};
