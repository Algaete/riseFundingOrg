namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static class MigrationSafety
{
    public const string ExpectedDatabaseName = "res";
    public const string ExpectedDatabaseConfigurationKey = "Migrations:ExpectedDatabaseName";
    public const string ExpectedServerConfigurationKey = "Migrations:ExpectedServerFqdn";
    public const string HistoryTableName = "FundingPlatform_SchemaVersions";
    public const string HistoryPrimaryKeyName = "FundingPlatform_PK_SchemaVersions";

    public static string ResolveExpectedDatabaseName(string? configuredDatabaseName)
    {
        var expected = string.IsNullOrWhiteSpace(configuredDatabaseName)
            ? ExpectedDatabaseName
            : configuredDatabaseName.Trim();
        if (expected.Length is < 1 or > 128 ||
            !IsAsciiLetterOrDigit(expected[0]) ||
            expected.Any(character =>
                !IsAsciiLetterOrDigit(character) && character is not '-' and not '_') ||
            new[] { "master", "model", "msdb", "tempdb" }.Contains(
                expected,
                StringComparer.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("invalid_expected_database_name");
        }

        return expected;
    }

    private static bool IsAsciiLetterOrDigit(char value) =>
        value is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9';

    public static bool IsExpectedDatabase(
        string? databaseName,
        string? configuredDatabaseName = null) =>
        string.Equals(
            databaseName?.Trim(),
            ResolveExpectedDatabaseName(configuredDatabaseName),
            StringComparison.OrdinalIgnoreCase);

    public static string? ResolveExpectedServerFqdn(string? configuredServerFqdn)
    {
        if (string.IsNullOrWhiteSpace(configuredServerFqdn))
        {
            return null;
        }

        var expected = configuredServerFqdn.Trim().ToLowerInvariant();
        var labels = expected.Split('.');
        if (expected.Length is < 23 or > 253 ||
            !expected.EndsWith(".database.windows.net", StringComparison.Ordinal) ||
            labels.Length != 4 ||
            !string.Equals(labels[1], "database", StringComparison.Ordinal) ||
            !string.Equals(labels[2], "windows", StringComparison.Ordinal) ||
            !string.Equals(labels[3], "net", StringComparison.Ordinal) ||
            labels.Any(label =>
                label.Length is < 1 or > 63 ||
                label[0] == '-' ||
                label[^1] == '-' ||
                label.Any(character =>
                    character is not (>= 'a' and <= 'z') and
                    not (>= '0' and <= '9') and not '-')))
        {
            throw new InvalidOperationException("invalid_expected_server_fqdn");
        }

        return expected;
    }

    public static IReadOnlyList<DatabaseObjectInfo> FindBaselineCollisions(
        int appliedMigrationCount,
        bool historyTableExists,
        IEnumerable<DatabaseObjectInfo> objects)
    {
        if (appliedMigrationCount != 0)
        {
            return [];
        }

        return objects
            .Where(item =>
                !historyTableExists ||
                (!string.Equals(item.Name, HistoryTableName, StringComparison.OrdinalIgnoreCase) &&
                 !string.Equals(item.Name, HistoryPrimaryKeyName, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(item => item.Type, StringComparer.Ordinal)
            .ThenBy(item => item.Name, StringComparer.Ordinal)
            .ToArray();
    }
}
