namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed record AppliedMigration(int Version, string Name, string Checksum, DateTime AppliedAtUtc);

public sealed record DatabaseObjectInfo(string Type, string Name);

public enum MigrationState
{
    Pending,
    Applied,
    ChecksumChanged,
    MissingLocalScript
}

public sealed record MigrationStatusItem(
    int Version,
    string Name,
    MigrationState State);

public sealed record MigrationStatus(
    bool TargetDatabaseVerified,
    bool HistoryTableExists,
    IReadOnlyList<MigrationStatusItem> Migrations,
    IReadOnlyList<DatabaseObjectInfo> Objects);

public sealed record MigrationRunResult(int ExecutedScripts, int ExecutedBatches);

public sealed record MigrationPreflightResult(
    MigrationRunResult Migrations,
    MigrationRunResult Tests);

public sealed record FullTextProvisioningStatus(string State)
{
    public bool IsReady => string.Equals(State, "ready", StringComparison.Ordinal);
}
