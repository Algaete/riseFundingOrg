namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static class MigrationHistory
{
    public static IReadOnlyList<MigrationStatusItem> BuildStatus(
        IReadOnlyList<SqlScript> local,
        IReadOnlyList<AppliedMigration> applied)
    {
        ArgumentNullException.ThrowIfNull(local);
        ArgumentNullException.ThrowIfNull(applied);

        var localByVersion = local.ToDictionary(item => item.Sequence);
        var appliedByVersion = applied.ToDictionary(item => item.Version);
        var status = new List<MigrationStatusItem>();

        foreach (var migration in local)
        {
            var state = !appliedByVersion.TryGetValue(migration.Sequence, out var recorded)
                ? MigrationState.Pending
                : string.Equals(recorded.Checksum, migration.Checksum, StringComparison.OrdinalIgnoreCase)
                    ? MigrationState.Applied
                    : MigrationState.ChecksumChanged;
            status.Add(new MigrationStatusItem(migration.Sequence, migration.Name, state));
        }

        status.AddRange(applied
            .Where(item => !localByVersion.ContainsKey(item.Version))
            .Select(item => new MigrationStatusItem(
                item.Version,
                SanitizeIdentifier(item.Name),
                MigrationState.MissingLocalScript)));

        return status.OrderBy(item => item.Version).ToArray();
    }

    public static void EnsureConsistent(
        IReadOnlyList<SqlScript> local,
        IReadOnlyList<AppliedMigration> applied)
    {
        var invalid = BuildStatus(local, applied)
            .FirstOrDefault(item => item.State is MigrationState.ChecksumChanged or MigrationState.MissingLocalScript);
        if (invalid is not null)
        {
            throw new MigrationException(
                invalid.State == MigrationState.ChecksumChanged
                    ? "migration_checksum_changed"
                    : "applied_migration_missing_locally",
                invalid.Version.ToString("D3"));
        }
    }

    private static string SanitizeIdentifier(string value) =>
        new(value
            .Where(character => char.IsLetterOrDigit(character) || character is '_' or '-' or ' ')
            .Take(128)
            .ToArray());
}
