using FundingPlatform.Infrastructure.Configuration;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

LocalEnvironmentLoader.TryLoad();

if (args.Length != 1 || !IsSupportedCommand(args[0]))
{
    PrintUsage();
    return 64;
}

try
{
    var configuration = FundingPlatformConfiguration.CreateFromEnvironment();
    var connectionFactory = new SqlConnectionFactory(configuration);

    if (args[0] == "--check-connection")
    {
        return await CheckConnectionAsync(connectionFactory);
    }

    var solutionRoot = SolutionRootLocator.Find();
    var migrations = SqlScriptCatalog.DiscoverMigrations(solutionRoot);
    IReadOnlyList<SqlScript> provisioning = [];
    if (args[0] is "--validate" or "--provision-full-text")
    {
        provisioning = SqlScriptCatalog.DiscoverProvisioning(solutionRoot);
        EnsureExpectedFullTextProvisioning(provisioning);
    }
    var runner = new DatabaseMigrationRunner(connectionFactory);

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
    command is "--check-connection" or "--status" or "--validate" or "--apply" or "--test"
        or "--provision-full-text";

static void PrintUsage() => Console.Error.WriteLine(
    "Uso: FundingPlatform.DatabaseMigrator " +
    "[--check-connection|--status|--validate|--apply|--test|--provision-full-text]");

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

static async Task<int> CheckConnectionAsync(ISqlConnectionFactory connectionFactory)
{
    var result = await new SqlConnectionVerifier(connectionFactory).CheckAsync();
    if (result.Succeeded)
    {
        Console.WriteLine("Conexión a Azure SQL verificada correctamente con SELECT 1.");
        return 0;
    }

    var sqlNumber = result.SqlErrorNumber is null
        ? string.Empty
        : $" Número de error SQL: {result.SqlErrorNumber.Value}.";
    Console.Error.WriteLine(
        $"Falló la verificación SELECT 1 en Azure SQL. Código: {result.Code}.{sqlNumber}");
    return 1;
}

static async Task<int> ShowStatusAsync(
    DatabaseMigrationRunner runner,
    IReadOnlyList<SqlScript> migrations)
{
    var status = await runner.GetStatusAsync(migrations);
    var fullText = await runner.GetFullTextProvisioningStatusAsync(migrations);
    Console.WriteLine("Base objetivo: res/verificada");
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
