using Dapper;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed class DatabaseMigrationRunner(
    ISqlConnectionFactory connectionFactory,
    string? expectedDatabaseName = null,
    string? expectedServerFqdn = null)
{
    private const string LockResource = "FundingPlatform:DatabaseMigrations";
    private const string FullTextLockResource = "FundingPlatform:FullTextProvisioning";
    private const int CommandTimeoutSeconds = 60;
    private readonly SqlDeploymentTargetVerifier targetVerifier = new(
        connectionFactory,
        expectedDatabaseName,
        expectedServerFqdn,
        requireExpectedServer:
            !string.Equals(
                MigrationSafety.ResolveExpectedDatabaseName(expectedDatabaseName),
                MigrationSafety.ExpectedDatabaseName,
                StringComparison.OrdinalIgnoreCase));

    public string ExpectedDatabaseName => targetVerifier.ExpectedDatabaseName;

    public string? ExpectedServerFqdn => targetVerifier.ExpectedServerFqdn;

    public async Task<MigrationStatus> GetStatusAsync(
        IReadOnlyList<SqlScript> localMigrations,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);

        var historyExists = await HistoryTableExistsAsync(connection, transaction: null, cancellationToken);
        var applied = historyExists
            ? await ReadAppliedAsync(connection, transaction: null, cancellationToken)
            : [];
        var objects = await ReadObjectsAsync(connection, transaction: null, cancellationToken);

        return new MigrationStatus(
            true,
            historyExists,
            MigrationHistory.BuildStatus(localMigrations, applied),
            objects);
    }

    public async Task<MigrationRunResult> ValidateAsync(
        IReadOnlyList<SqlScript> migrations,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await AcquireLockAsync(connection, transaction, cancellationToken);
            var applied = await ReadAppliedIfPresentAsync(connection, transaction, cancellationToken);
            MigrationHistory.EnsureConsistent(migrations, applied);
            await EnsureNoBaselineCollisionAsync(connection, transaction, applied.Count, cancellationToken);
            await EnsureHistoryTableAsync(connection, transaction, cancellationToken);
            var result = await ExecutePendingAsync(
                connection,
                transaction,
                migrations,
                applied,
                recordHistory: true,
                cancellationToken);
            await transaction.RollbackAsync(CancellationToken.None);
            return result;
        }
        catch
        {
            await RollbackIfNeededAsync(transaction);
            throw;
        }
    }

    public async Task<MigrationRunResult> ApplyAsync(
        IReadOnlyList<SqlScript> migrations,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);

        var executedScripts = 0;
        var executedBatches = 0;

        if (migrations.Count == 0)
        {
            await using var preflightTransaction =
                (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                await AcquireLockAsync(connection, preflightTransaction, cancellationToken);
                var applied = await ReadAppliedIfPresentAsync(
                    connection,
                    preflightTransaction,
                    cancellationToken);
                MigrationHistory.EnsureConsistent(migrations, applied);
                await EnsureNoBaselineCollisionAsync(
                    connection,
                    preflightTransaction,
                    applied.Count,
                    cancellationToken);
                await preflightTransaction.RollbackAsync(CancellationToken.None);
            }
            catch
            {
                await RollbackIfNeededAsync(preflightTransaction);
                throw;
            }
        }

        foreach (var migration in migrations)
        {
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
            try
            {
                await AcquireLockAsync(connection, transaction, cancellationToken);
                var applied = await ReadAppliedIfPresentAsync(connection, transaction, cancellationToken);
                MigrationHistory.EnsureConsistent(migrations, applied);
                await EnsureNoBaselineCollisionAsync(connection, transaction, applied.Count, cancellationToken);

                if (applied.Any(item => item.Version == migration.Sequence))
                {
                    await transaction.RollbackAsync(CancellationToken.None);
                    continue;
                }

                await EnsureHistoryTableAsync(connection, transaction, cancellationToken);
                var result = await ExecutePendingAsync(
                    connection,
                    transaction,
                    [migration],
                    applied,
                    recordHistory: true,
                    cancellationToken);
                await transaction.CommitAsync(cancellationToken);
                executedScripts += result.ExecutedScripts;
                executedBatches += result.ExecutedBatches;
            }
            catch
            {
                await RollbackIfNeededAsync(transaction);
                throw;
            }
        }

        return new MigrationRunResult(executedScripts, executedBatches);
    }

    public async Task<MigrationRunResult> TestAsync(
        IReadOnlyList<SqlScript> migrations,
        IReadOnlyList<SqlScript> tests,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await AcquireLockAsync(connection, transaction, cancellationToken);
            var applied = await ReadAppliedIfPresentAsync(connection, transaction, cancellationToken);
            MigrationHistory.EnsureConsistent(migrations, applied);
            if (MigrationHistory.BuildStatus(migrations, applied).Any(item => item.State != MigrationState.Applied))
            {
                throw new MigrationException("schema_not_fully_applied");
            }

            var result = await ExecutePendingAsync(
                connection,
                transaction,
                tests,
                applied: [],
                recordHistory: false,
                cancellationToken);
            await transaction.RollbackAsync(CancellationToken.None);
            return result;
        }
        catch
        {
            await RollbackIfNeededAsync(transaction);
            throw;
        }
    }

    public async Task<MigrationRunResult> ProvisionFullTextAsync(
        IReadOnlyList<SqlScript> migrations,
        IReadOnlyList<SqlScript> provisioningScripts,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);

        var migrationLockAcquired = false;
        var fullTextLockAcquired = false;
        try
        {
            await AcquireSessionLockAsync(
                connection, LockResource, cancellationToken);
            migrationLockAcquired = true;
            await AcquireSessionLockAsync(
                connection, FullTextLockResource, cancellationToken);
            fullTextLockAcquired = true;

            var applied = await ReadAppliedIfPresentAsync(
                connection, transaction: null, cancellationToken);
            MigrationHistory.EnsureConsistent(migrations, applied);
            var migration018 = MigrationHistory.BuildStatus(migrations, applied)
                .SingleOrDefault(item => item.Version == 18);
            if (migration018?.State != MigrationState.Applied)
            {
                throw new MigrationException("full_text_requires_migration_018");
            }

            var executedBatches = 0;
            foreach (var script in provisioningScripts)
            {
                try
                {
                    foreach (var batch in script.Batches)
                    {
                        await connection.ExecuteAsync(new CommandDefinition(
                            batch,
                            commandTimeout: CommandTimeoutSeconds,
                            cancellationToken: cancellationToken));
                        executedBatches++;
                    }
                }
                catch (SqlException exception)
                {
                    throw new MigrationException(
                        "provisioning_script_failed",
                        script.Name,
                        exception.Number,
                        exception);
                }
            }

            return new MigrationRunResult(provisioningScripts.Count, executedBatches);
        }
        finally
        {
            if (fullTextLockAcquired)
            {
                await ReleaseSessionLockBestEffortAsync(
                    connection, FullTextLockResource);
            }
            if (migrationLockAcquired)
            {
                await ReleaseSessionLockBestEffortAsync(connection, LockResource);
            }
        }
    }

    public async Task<FullTextProvisioningStatus> GetFullTextProvisioningStatusAsync(
        IReadOnlyList<SqlScript> migrations,
        CancellationToken cancellationToken = default)
    {
        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, transaction: null, cancellationToken);

        var applied = await ReadAppliedIfPresentAsync(
            connection, transaction: null, cancellationToken);
        var migration018 = MigrationHistory.BuildStatus(migrations, applied)
            .SingleOrDefault(item => item.Version == 18);
        if (migration018 is null || migration018.State == MigrationState.Pending)
        {
            return new FullTextProvisioningStatus("migration-pending");
        }

        if (migration018.State != MigrationState.Applied)
        {
            return new FullTextProvisioningStatus("migration-drift");
        }

        var state = await connection.QuerySingleAsync<string>(new CommandDefinition(
            """
            DECLARE @ObjectId INT =
                OBJECT_ID(N'dbo.FundingPlatform_FundingOpportunities');
            DECLARE @ExpectedCatalogId INT =
                (SELECT fulltext_catalog_id FROM sys.fulltext_catalogs
                 WHERE name = N'FundingPlatform_FundingSearchCatalog'
                   AND is_accent_sensitivity_on = 0
                   AND principal_id = DATABASE_PRINCIPAL_ID(N'dbo'));
            DECLARE @ExpectedIndexId INT =
                (SELECT index_id FROM sys.indexes
                 WHERE object_id = @ObjectId
                   AND name = N'FundingPlatform_PK_FundingOpportunities');

            SELECT CONVERT(NVARCHAR(30), CASE
                WHEN @ObjectId IS NULL OR @ExpectedIndexId IS NULL
                  OR OBJECT_ID(N'dbo.FundingPlatform_ifn_FundingOpportunityPublicReady', N'IF') IS NULL
                    THEN N'drift'
                WHEN COALESCE(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled'), 0) <> 1
                    THEN N'unavailable'
                WHEN EXISTS
                    (SELECT 1 FROM sys.fulltext_catalogs
                     WHERE name = N'FundingPlatform_FundingSearchCatalog'
                       AND (is_accent_sensitivity_on <> 0
                            OR principal_id <> DATABASE_PRINCIPAL_ID(N'dbo')))
                    THEN N'drift'
                WHEN @ExpectedCatalogId IS NULL AND EXISTS
                    (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = @ObjectId)
                    THEN N'drift'
                WHEN EXISTS
                    (SELECT 1 FROM sys.fulltext_indexes
                     WHERE fulltext_catalog_id = @ExpectedCatalogId
                       AND object_id <> @ObjectId)
                    THEN N'drift'
                WHEN @ExpectedCatalogId IS NULL OR NOT EXISTS
                    (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = @ObjectId)
                    THEN N'not-provisioned'
                WHEN NOT EXISTS
                    (SELECT 1 FROM sys.fulltext_indexes
                     WHERE object_id = @ObjectId
                       AND fulltext_catalog_id = @ExpectedCatalogId
                       AND unique_index_id = @ExpectedIndexId
                       AND change_tracking_state_desc = N'AUTO'
                       AND stoplist_id = 0
                       AND property_list_id IS NULL
                       AND is_enabled = 1)
                    THEN N'drift'
                WHEN (SELECT COUNT_BIG(1)
                      FROM sys.fulltext_index_columns AS fic
                      INNER JOIN sys.columns AS columns
                        ON columns.object_id = fic.object_id
                       AND columns.column_id = fic.column_id
                      WHERE fic.object_id = @ObjectId
                        AND columns.name IN
                            (N'Title', N'Description', N'Summary', N'SponsorName',
                             N'EligibilityDescription', N'Requirements')
                        AND fic.language_id = 0
                        AND fic.statistical_semantics = 0) <> 6
                  OR EXISTS
                    (SELECT 1
                     FROM sys.fulltext_index_columns AS fic
                     INNER JOIN sys.columns AS columns
                       ON columns.object_id = fic.object_id
                      AND columns.column_id = fic.column_id
                     WHERE fic.object_id = @ObjectId
                       AND (columns.name NOT IN
                            (N'Title', N'Description', N'Summary', N'SponsorName',
                             N'EligibilityDescription', N'Requirements')
                            OR fic.language_id <> 0
                            OR fic.statistical_semantics <> 0))
                    THEN N'drift'
                WHEN OBJECTPROPERTYEX(@ObjectId, 'TableFulltextFailCount') <> 0
                  OR OBJECTPROPERTYEX(@ObjectId, 'TableFullTextPopulateStatus') = 6
                    THEN N'population-failed'
                WHEN FULLTEXTCATALOGPROPERTY
                     (N'FundingPlatform_FundingSearchCatalog', 'PopulateStatus') = 0
                 AND OBJECTPROPERTYEX(@ObjectId, 'TableFullTextPopulateStatus') = 0
                 AND EXISTS
                    (SELECT 1 FROM sys.fulltext_indexes
                     WHERE object_id = @ObjectId AND has_crawl_completed = 1)
                    THEN N'ready'
                ELSE N'populating'
            END);
            """,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        return new FullTextProvisioningStatus(state);
    }

    private static async Task<MigrationRunResult> ExecutePendingAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        IReadOnlyList<SqlScript> scripts,
        IReadOnlyList<AppliedMigration> applied,
        bool recordHistory,
        CancellationToken cancellationToken)
    {
        var appliedVersions = applied.Select(item => item.Version).ToHashSet();
        var executedScripts = 0;
        var executedBatches = 0;

        foreach (var script in scripts.Where(item => !appliedVersions.Contains(item.Sequence)))
        {
            try
            {
                foreach (var batch in script.Batches)
                {
                    await connection.ExecuteAsync(new CommandDefinition(
                        batch,
                        transaction: transaction,
                        commandTimeout: CommandTimeoutSeconds,
                        cancellationToken: cancellationToken));
                    executedBatches++;
                }

                if (recordHistory)
                {
                    await connection.ExecuteAsync(new CommandDefinition(
                        """
                        INSERT INTO [dbo].[FundingPlatform_SchemaVersions]
                            ([Version], [Name], [Checksum], [AppliedAtUtc])
                        VALUES (@Version, @Name, @Checksum, SYSUTCDATETIME());
                        """,
                        new { Version = script.Sequence, script.Name, script.Checksum },
                        transaction,
                        commandTimeout: CommandTimeoutSeconds,
                        cancellationToken: cancellationToken));
                }
            }
            catch (SqlException exception)
            {
                throw new MigrationException(
                    "sql_script_failed", script.Name, exception.Number, exception);
            }

            executedScripts++;
        }

        return new MigrationRunResult(executedScripts, executedBatches);
    }

    private static async Task AcquireSessionLockAsync(
        SqlConnection connection,
        string resource,
        CancellationToken cancellationToken)
    {
        try
        {
            var result = await connection.QuerySingleAsync<int>(new CommandDefinition(
                """
                DECLARE @result INT;
                EXEC @result = sys.sp_getapplock
                    @Resource = @Resource,
                    @LockMode = N'Exclusive',
                    @LockOwner = N'Session',
                    @LockTimeout = 15000;
                SELECT @result;
                """,
                new { Resource = resource },
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: cancellationToken));
            if (result < 0)
            {
                throw new MigrationException("provisioning_lock_not_acquired");
            }
        }
        catch
        {
            /* A response can be lost after SQL Server acquired a session lock.
               Never return that physical session to the pool in an uncertain state. */
            ClearPoolBestEffort(connection);
            throw;
        }
    }

    private static async Task ReleaseSessionLockBestEffortAsync(
        SqlConnection connection,
        string resource)
    {
        try
        {
            var result = await connection.QuerySingleAsync<int>(new CommandDefinition(
                """
                DECLARE @result INT;
                EXEC @result = sys.sp_releaseapplock
                    @Resource = @Resource,
                    @LockOwner = N'Session';
                SELECT @result;
                """,
                new { Resource = resource },
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: CancellationToken.None));
            if (result < 0)
            {
                ClearPoolBestEffort(connection);
            }
        }
        catch
        {
            ClearPoolBestEffort(connection);
        }
    }

    private static void ClearPoolBestEffort(SqlConnection connection)
    {
        try
        {
            SqlConnection.ClearPool(connection);
        }
        catch
        {
            // Closing a non-pooled/broken connection still releases server state.
        }
    }

    private async Task EnsureTargetDatabaseAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        _ = await targetVerifier.VerifyConnectionAsync(
            connection, transaction, cancellationToken);
    }

    private static async Task AcquireLockAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        var result = await connection.QuerySingleAsync<int>(new CommandDefinition(
            """
            DECLARE @result int;
            EXEC @result = sys.sp_getapplock
                @Resource = @Resource,
                @LockMode = N'Exclusive',
                @LockOwner = N'Transaction',
                @LockTimeout = 15000;
            SELECT @result;
            """,
            new { Resource = LockResource },
            transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));

        if (result < 0)
        {
            throw new MigrationException("migration_lock_not_acquired");
        }
    }

    private static async Task<bool> HistoryTableExistsAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken) =>
        await connection.QuerySingleAsync<bool>(new CommandDefinition(
            "SELECT CONVERT(bit, CASE WHEN OBJECT_ID(N'[dbo].[FundingPlatform_SchemaVersions]', N'U') IS NULL THEN 0 ELSE 1 END);",
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));

    private static async Task<IReadOnlyList<AppliedMigration>> ReadAppliedIfPresentAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken) =>
        await HistoryTableExistsAsync(connection, transaction, cancellationToken)
            ? await ReadAppliedAsync(connection, transaction, cancellationToken)
            : [];

    private static async Task<IReadOnlyList<AppliedMigration>> ReadAppliedAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        var rows = await connection.QueryAsync<AppliedMigration>(new CommandDefinition(
            """
            SELECT [Version], [Name], [Checksum], [AppliedAtUtc]
            FROM [dbo].[FundingPlatform_SchemaVersions]
            ORDER BY [Version];
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        return rows.AsList();
    }

    private static Task EnsureHistoryTableAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        CancellationToken cancellationToken) =>
        connection.ExecuteAsync(new CommandDefinition(
            """
            IF OBJECT_ID(N'[dbo].[FundingPlatform_SchemaVersions]', N'U') IS NULL
            BEGIN
                CREATE TABLE [dbo].[FundingPlatform_SchemaVersions]
                (
                    [Version] int NOT NULL,
                    [Name] nvarchar(260) NOT NULL,
                    [Checksum] char(64) NOT NULL,
                    [AppliedAtUtc] datetime2(7) NOT NULL,
                    CONSTRAINT [FundingPlatform_PK_SchemaVersions] PRIMARY KEY ([Version])
                );
            END;
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));

    private static async Task<IReadOnlyList<DatabaseObjectInfo>> ReadObjectsAsync(
        SqlConnection connection,
        SqlTransaction? transaction,
        CancellationToken cancellationToken)
    {
        var rows = await connection.QueryAsync<DatabaseObjectInfo>(new CommandDefinition(
            """
            SELECT [Type], [Name]
            FROM
            (
                SELECT CONVERT(nvarchar(60), [type_desc]) AS [Type], CONVERT(nvarchar(128), [name]) AS [Name]
                FROM sys.objects
                WHERE [name] LIKE N'FundingPlatform[_]%'
                  AND [type] <> N'TT'
                UNION ALL
                SELECT N'USER_DEFINED_TYPE', CONVERT(nvarchar(128), [name])
                FROM sys.types
                WHERE [is_user_defined] = 1 AND [name] LIKE N'FundingPlatform[_]%'
                UNION ALL
                SELECT N'INDEX', CONVERT(nvarchar(128), [name])
                FROM sys.indexes
                WHERE [name] LIKE N'FundingPlatform[_]%'
                UNION ALL
                SELECT N'FULLTEXT_CATALOG', CONVERT(nvarchar(128), [name])
                FROM sys.fulltext_catalogs
                WHERE [name] LIKE N'FundingPlatform[_]%'
            ) AS inventory
            ORDER BY [Type], [Name];
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));

        return rows
            .Select(item => new DatabaseObjectInfo(
                SanitizeIdentifier(item.Type),
                SanitizeIdentifier(item.Name)))
            .ToArray();
    }

    private static async Task EnsureNoBaselineCollisionAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        int appliedMigrationCount,
        CancellationToken cancellationToken)
    {
        var historyTableExists = await HistoryTableExistsAsync(
            connection,
            transaction,
            cancellationToken);
        var collisions = MigrationSafety.FindBaselineCollisions(
            appliedMigrationCount,
            historyTableExists,
            await ReadObjectsAsync(connection, transaction, cancellationToken));
        if (collisions.Count > 0)
        {
            throw new MigrationException(
                "untracked_prefixed_objects",
                string.Join(",", collisions.Select(item => $"{item.Type}:{item.Name}")));
        }
    }

    private static async Task RollbackIfNeededAsync(SqlTransaction transaction)
    {
        try
        {
            if (transaction.Connection is not null)
            {
                await transaction.RollbackAsync(CancellationToken.None);
            }
        }
        catch (InvalidOperationException)
        {
            // The server may already have rolled back the transaction after
            // XACT_ABORT. Preserve the original migration failure.
        }
        catch (SqlException)
        {
            // Disposing the connection is the final rollback safeguard. Never
            // mask the original SQL error with a secondary rollback failure.
        }
    }

    private static string SanitizeIdentifier(string value) =>
        new(value
            .Where(character => char.IsLetterOrDigit(character) || character is '_' or '-' or ' ')
            .Take(128)
            .ToArray());
}
