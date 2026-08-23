namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static class MigrationSafety
{
    public const string ExpectedDatabaseName = "res";
    public const string HistoryTableName = "FundingPlatform_SchemaVersions";
    public const string HistoryPrimaryKeyName = "FundingPlatform_PK_SchemaVersions";

    public static bool IsExpectedDatabase(string? databaseName) =>
        string.Equals(databaseName?.Trim(), ExpectedDatabaseName, StringComparison.OrdinalIgnoreCase);

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
