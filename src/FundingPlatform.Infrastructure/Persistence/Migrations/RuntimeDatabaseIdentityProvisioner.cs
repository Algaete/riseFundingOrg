using Dapper;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed class RuntimeDatabaseIdentityProvisioner
{
    private const string LockResource = "FundingPlatform:RuntimeIdentityProvisioning";
    private const int CommandTimeoutSeconds = 60;

    internal const string CreateUserSql = """
        DECLARE @QuotedUserName nvarchar(258) = QUOTENAME(@UserName);
        IF @QuotedUserName IS NULL
            THROW 54900, N'Runtime database user name is invalid.', 1;

        DECLARE @CreateSql nvarchar(max) =
            N'CREATE USER ' + @QuotedUserName
            + N' WITH SID = ' + CONVERT(nvarchar(34), CONVERT(binary(16), @Sid), 1)
            + N', TYPE = E;';
        EXEC sys.sp_executesql @CreateSql;
        """;

    internal const string AddRoleMemberSql = """
        DECLARE @QuotedRoleName nvarchar(258) = QUOTENAME(@RoleName);
        DECLARE @QuotedUserName nvarchar(258) = QUOTENAME(@UserName);
        IF @QuotedRoleName IS NULL OR @QuotedUserName IS NULL
            THROW 54901, N'Runtime database role membership identifier is invalid.', 1;

        EXEC sys.sp_executesql
            N'ALTER ROLE ' + @QuotedRoleName + N' ADD MEMBER ' + @QuotedUserName + N';';
        """;

    private readonly ISqlConnectionFactory connectionFactory;
    private readonly SqlDeploymentTargetVerifier targetVerifier;

    public RuntimeDatabaseIdentityProvisioner(
        ISqlConnectionFactory connectionFactory,
        string? expectedDatabaseName,
        string? expectedServerFqdn)
    {
        ArgumentNullException.ThrowIfNull(connectionFactory);
        if (string.IsNullOrWhiteSpace(expectedDatabaseName))
        {
            throw new MigrationException("runtime_identity_expected_database_required");
        }

        this.connectionFactory = connectionFactory;
        targetVerifier = new SqlDeploymentTargetVerifier(
            connectionFactory,
            expectedDatabaseName,
            expectedServerFqdn,
            requireExpectedServer: true);
    }

    public string ExpectedDatabaseName => targetVerifier.ExpectedDatabaseName;

    public string ExpectedServerFqdn => targetVerifier.ExpectedServerFqdn!;

    public Task<RuntimeDatabaseIdentityProvisioningResult> ProvisionAndVerifyAsync(
        IReadOnlyList<SqlScript> localMigrations,
        RuntimeDatabaseIdentityPlan plan,
        CancellationToken cancellationToken = default) =>
        ExecuteAsync(localMigrations, plan, provision: true, cancellationToken);

    public Task<RuntimeDatabaseIdentityProvisioningResult> VerifyAsync(
        IReadOnlyList<SqlScript> localMigrations,
        RuntimeDatabaseIdentityPlan plan,
        CancellationToken cancellationToken = default) =>
        ExecuteAsync(localMigrations, plan, provision: false, cancellationToken);

    private async Task<RuntimeDatabaseIdentityProvisioningResult> ExecuteAsync(
        IReadOnlyList<SqlScript> localMigrations,
        RuntimeDatabaseIdentityPlan plan,
        bool provision,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(localMigrations);
        ArgumentNullException.ThrowIfNull(plan);

        await using var connection = connectionFactory.CreateConnection();
        await connection.OpenAsync(cancellationToken);
        await EnsureTargetDatabaseAsync(connection, cancellationToken);
        await using var transaction =
            (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);

        try
        {
            await AcquireLockAsync(connection, transaction, cancellationToken);
            await EnsureMigration027AppliedAsync(
                connection, transaction, localMigrations, cancellationToken);
            await EnsureRolesExistAsync(connection, transaction, cancellationToken);

            var createdUsers = 0;
            var addedMemberships = 0;
            foreach (var identity in plan.DatabaseUsers)
            {
                var result = await EnsureIdentityAsync(
                    connection, transaction, identity, provision, cancellationToken);
                createdUsers += result.CreatedUser ? 1 : 0;
                addedMemberships += result.AddedMembership ? 1 : 0;
            }

            await EnsureRuntimeRoleMembersExactAsync(
                connection, transaction, plan.DatabaseUsers, cancellationToken);

            foreach (var identity in plan.IdentitiesWithoutDatabaseAccess)
            {
                await EnsureIdentityAbsentAsync(
                    connection, transaction, identity, cancellationToken);
            }

            if (provision)
            {
                await transaction.CommitAsync(cancellationToken);
            }
            else
            {
                await transaction.RollbackAsync(CancellationToken.None);
            }

            return new RuntimeDatabaseIdentityProvisioningResult(
                createdUsers,
                addedMemberships,
                plan.DatabaseUsers.Count,
                plan.IdentitiesWithoutDatabaseAccess.Count);
        }
        catch (MigrationException)
        {
            await RollbackIfNeededAsync(transaction);
            throw;
        }
        catch (SqlException exception)
        {
            await RollbackIfNeededAsync(transaction);
            throw new MigrationException(
                "runtime_identity_sql_failed",
                databaseErrorNumber: exception.Number,
                innerException: exception);
        }
        catch
        {
            await RollbackIfNeededAsync(transaction);
            throw;
        }
    }

    private static async Task<(bool CreatedUser, bool AddedMembership)> EnsureIdentityAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        RuntimeDatabaseIdentity identity,
        bool provision,
        CancellationToken cancellationToken)
    {
        var sid = RuntimeDatabaseIdentityPlan.ClientIdToSid(identity.ClientId);
        var principals = await ReadMatchingPrincipalsAsync(
            connection, transaction, identity.UserName, sid, cancellationToken);
        var exactPrincipal = FindExactPrincipal(principals, identity.UserName, sid);
        var createdUser = false;

        if (exactPrincipal is not null && principals.Count != 1)
        {
            throw new MigrationException(
                "runtime_identity_principal_collision",
                identity.UserName);
        }

        if (exactPrincipal is null)
        {
            if (principals.Count > 0)
            {
                throw new MigrationException(
                    principals.Any(item => SidMatches(item.Sid, sid))
                        ? "runtime_identity_sid_bound_to_different_user"
                        : "runtime_identity_user_name_collision",
                    identity.UserName);
            }
            if (!provision)
            {
                throw new MigrationException(
                    "runtime_identity_user_missing",
                    identity.UserName);
            }

            await connection.ExecuteAsync(new CommandDefinition(
                CreateUserSql,
                new { UserName = identity.UserName, Sid = sid },
                transaction,
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: cancellationToken));
            createdUser = true;
            principals = await ReadMatchingPrincipalsAsync(
                connection, transaction, identity.UserName, sid, cancellationToken);
            exactPrincipal = FindExactPrincipal(principals, identity.UserName, sid);
        }

        if (exactPrincipal is null ||
            !string.Equals(exactPrincipal.Type, "E", StringComparison.Ordinal) ||
            !string.Equals(
                exactPrincipal.AuthenticationTypeDescription,
                "EXTERNAL",
                StringComparison.Ordinal))
        {
            throw new MigrationException(
                "runtime_identity_principal_metadata_mismatch",
                identity.UserName);
        }

        await EnsureNoUnexpectedDirectPrivilegesOrOwnershipAsync(
            connection,
            transaction,
            exactPrincipal.PrincipalId,
            identity.UserName,
            cancellationToken);

        var roles = await ReadRoleMembershipsAsync(
            connection, transaction, exactPrincipal.PrincipalId, cancellationToken);
        if (roles.Any(role => !string.Equals(role, identity.RoleName, StringComparison.Ordinal)))
        {
            throw new MigrationException(
                "runtime_identity_unexpected_role_membership",
                identity.UserName);
        }

        var addedMembership = false;
        if (!roles.Contains(identity.RoleName, StringComparer.Ordinal))
        {
            if (!provision)
            {
                throw new MigrationException(
                    "runtime_identity_required_role_missing",
                    identity.UserName);
            }

            await connection.ExecuteAsync(new CommandDefinition(
                AddRoleMemberSql,
                new { identity.RoleName, identity.UserName },
                transaction,
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: cancellationToken));
            addedMembership = true;
            roles = await ReadRoleMembershipsAsync(
                connection, transaction, exactPrincipal.PrincipalId, cancellationToken);
        }

        if (roles.Count != 1 ||
            !string.Equals(roles[0], identity.RoleName, StringComparison.Ordinal))
        {
            throw new MigrationException(
                "runtime_identity_role_membership_verification_failed",
                identity.UserName);
        }

        return (createdUser, addedMembership);
    }

    private static async Task EnsureIdentityAbsentAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        RuntimeDatabaseAbsentIdentity identity,
        CancellationToken cancellationToken)
    {
        var sid = RuntimeDatabaseIdentityPlan.ClientIdToSid(identity.ClientId);
        var principals = await ReadMatchingPrincipalsAsync(
            connection, transaction, identity.UserName, sid, cancellationToken);
        if (principals.Count > 0)
        {
            throw new MigrationException(
                "runtime_identity_must_not_have_database_user",
                identity.UserName);
        }
    }

    private static RuntimeDatabasePrincipal? FindExactPrincipal(
        IReadOnlyList<RuntimeDatabasePrincipal> principals,
        string userName,
        byte[] sid) =>
        principals.SingleOrDefault(item =>
            string.Equals(item.Name, userName, StringComparison.Ordinal) &&
            SidMatches(item.Sid, sid));

    private static bool SidMatches(byte[]? actual, byte[] expected) =>
        actual is not null && actual.AsSpan().SequenceEqual(expected);

    private static async Task<IReadOnlyList<RuntimeDatabasePrincipal>> ReadMatchingPrincipalsAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        string userName,
        byte[] sid,
        CancellationToken cancellationToken)
    {
        var rows = await connection.QueryAsync<RuntimeDatabasePrincipal>(new CommandDefinition(
            """
            SELECT
                principal_id AS PrincipalId,
                CONVERT(nvarchar(128), name) AS Name,
                CONVERT(varbinary(85), sid) AS Sid,
                CONVERT(nchar(1), type) AS Type,
                CONVERT(nvarchar(60), authentication_type_desc) AS AuthenticationTypeDescription
            FROM sys.database_principals
            WHERE name = @UserName OR sid = @Sid;
            """,
            new { UserName = userName, Sid = sid },
            transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        return rows.AsList();
    }

    private static async Task EnsureRuntimeRoleMembersExactAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        IReadOnlyList<RuntimeDatabaseIdentity> expectedIdentities,
        CancellationToken cancellationToken)
    {
        var rows = (await connection.QueryAsync<RuntimeDatabaseRoleMember>(new CommandDefinition(
            """
            SELECT
                CONVERT(nvarchar(128), roles.name) AS RoleName,
                CONVERT(nvarchar(128), members.name) AS UserName,
                CONVERT(varbinary(85), members.sid) AS Sid,
                CONVERT(nchar(1), members.type) AS Type
            FROM sys.database_role_members AS memberships
            INNER JOIN sys.database_principals AS roles
                ON roles.principal_id = memberships.role_principal_id
            INNER JOIN sys.database_principals AS members
                ON members.principal_id = memberships.member_principal_id
            WHERE roles.name IN
                (N'FundingPlatform_ApiRuntimeRole',
                 N'FundingPlatform_GeneralWorkerRole',
                 N'FundingPlatform_ExtractionWorkerRole')
            ORDER BY roles.name, members.name;
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken))).AsList();

        foreach (var expected in expectedIdentities)
        {
            var roleMembers = rows
                .Where(item => string.Equals(
                    item.RoleName, expected.RoleName, StringComparison.Ordinal))
                .ToArray();
            var expectedSid = RuntimeDatabaseIdentityPlan.ClientIdToSid(expected.ClientId);
            if (roleMembers.Length != 1 ||
                !string.Equals(
                    roleMembers[0].UserName,
                    expected.UserName,
                    StringComparison.Ordinal) ||
                !SidMatches(roleMembers[0].Sid, expectedSid) ||
                !string.Equals(roleMembers[0].Type, "E", StringComparison.Ordinal))
            {
                throw new MigrationException(
                    "runtime_identity_role_has_unexpected_members",
                    expected.RoleName);
            }
        }
    }

    private static async Task EnsureNoUnexpectedDirectPrivilegesOrOwnershipAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        int principalId,
        string userName,
        CancellationToken cancellationToken)
    {
        var hasUnexpectedPrivilege = await connection.QuerySingleAsync<bool>(
            new CommandDefinition(
                """
                SELECT CONVERT(bit, CASE WHEN
                    EXISTS
                        (SELECT 1
                         FROM sys.database_permissions AS permissions
                         WHERE permissions.grantee_principal_id = @PrincipalId
                           AND NOT
                               (permissions.class = 0
                                AND permissions.major_id = 0
                                AND permissions.minor_id = 0
                                AND permissions.permission_name = N'CONNECT'
                                AND permissions.state = N'G'))
                    OR EXISTS
                        (SELECT 1
                         FROM sys.schemas AS schemas
                         WHERE schemas.principal_id = @PrincipalId)
                    OR EXISTS
                        (SELECT 1
                         FROM sys.database_principals AS ownedPrincipals
                         WHERE ownedPrincipals.owning_principal_id = @PrincipalId)
                    THEN 1 ELSE 0 END);
                """,
                new { PrincipalId = principalId },
                transaction,
                commandTimeout: CommandTimeoutSeconds,
                cancellationToken: cancellationToken));
        if (hasUnexpectedPrivilege)
        {
            throw new MigrationException(
                "runtime_identity_direct_privilege_or_ownership_detected",
                userName);
        }
    }

    private static async Task<IReadOnlyList<string>> ReadRoleMembershipsAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        int principalId,
        CancellationToken cancellationToken)
    {
        var rows = await connection.QueryAsync<string>(new CommandDefinition(
            """
            SELECT CONVERT(nvarchar(128), roles.name)
            FROM sys.database_role_members AS memberships
            INNER JOIN sys.database_principals AS roles
                ON roles.principal_id = memberships.role_principal_id
            WHERE memberships.member_principal_id = @PrincipalId
            ORDER BY roles.name;
            """,
            new { PrincipalId = principalId },
            transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        return rows.AsList();
    }

    private async Task EnsureTargetDatabaseAsync(
        SqlConnection connection,
        CancellationToken cancellationToken)
    {
        _ = await targetVerifier.VerifyConnectionAsync(
            connection, transaction: null, cancellationToken);
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
            throw new MigrationException("runtime_identity_lock_not_acquired");
        }
    }

    private static async Task EnsureMigration027AppliedAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        IReadOnlyList<SqlScript> localMigrations,
        CancellationToken cancellationToken)
    {
        var migration027 = localMigrations.SingleOrDefault(item => item.Sequence == 27);
        if (migration027 is null ||
            !string.Equals(
                migration027.Name,
                "runtime_database_roles",
                StringComparison.Ordinal))
        {
            throw new MigrationException("runtime_identity_local_migration_027_missing");
        }

        var historyExists = await connection.QuerySingleAsync<bool>(new CommandDefinition(
            "SELECT CONVERT(bit, CASE WHEN OBJECT_ID(N'dbo.FundingPlatform_SchemaVersions', N'U') IS NULL THEN 0 ELSE 1 END);",
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        if (!historyExists)
        {
            throw new MigrationException("runtime_identity_migration_027_not_applied");
        }

        var rows = await connection.QueryAsync<AppliedMigration>(new CommandDefinition(
            """
            SELECT [Version], [Name], [Checksum], [AppliedAtUtc]
            FROM dbo.FundingPlatform_SchemaVersions
            ORDER BY [Version];
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken));
        var applied = rows.AsList();
        MigrationHistory.EnsureConsistent(localMigrations, applied);
        if (MigrationHistory.BuildStatus(localMigrations, applied)
            .Single(item => item.Version == 27).State != MigrationState.Applied)
        {
            throw new MigrationException("runtime_identity_migration_027_not_applied");
        }
    }

    private static async Task EnsureRolesExistAsync(
        SqlConnection connection,
        SqlTransaction transaction,
        CancellationToken cancellationToken)
    {
        string[] expectedRoles =
        [
            RuntimeDatabaseIdentityPlan.ApiRuntimeRole,
            RuntimeDatabaseIdentityPlan.GeneralWorkerRole,
            RuntimeDatabaseIdentityPlan.ExtractionWorkerRole
        ];
        var roles = (await connection.QueryAsync<string>(new CommandDefinition(
            """
            SELECT CONVERT(nvarchar(128), roles.name)
            FROM sys.database_principals AS roles
            WHERE roles.type = N'R'
              AND roles.owning_principal_id = DATABASE_PRINCIPAL_ID(N'dbo')
              AND roles.name IN
                  (N'FundingPlatform_ApiRuntimeRole',
                   N'FundingPlatform_GeneralWorkerRole',
                   N'FundingPlatform_ExtractionWorkerRole')
              AND NOT EXISTS
                  (SELECT 1
                   FROM sys.database_role_members AS memberships
                   WHERE memberships.member_principal_id =
                         roles.principal_id)
            ORDER BY roles.name;
            """,
            transaction: transaction,
            commandTimeout: CommandTimeoutSeconds,
            cancellationToken: cancellationToken))).AsList();
        if (!roles.OrderBy(item => item, StringComparer.Ordinal)
            .SequenceEqual(expectedRoles.OrderBy(item => item, StringComparer.Ordinal), StringComparer.Ordinal))
        {
            throw new MigrationException("runtime_identity_roles_missing_or_invalid");
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
            // Preserve the original failure if SQL already ended the transaction.
        }
        catch (SqlException)
        {
            // Disposing the connection remains the final rollback safeguard.
        }
    }

    private sealed record RuntimeDatabasePrincipal(
        int PrincipalId,
        string Name,
        byte[]? Sid,
        string Type,
        string AuthenticationTypeDescription);

    private sealed record RuntimeDatabaseRoleMember(
        string RoleName,
        string UserName,
        byte[]? Sid,
        string Type);
}

public sealed record RuntimeDatabaseIdentityProvisioningResult(
    int CreatedUsers,
    int AddedMemberships,
    int VerifiedUsers,
    int VerifiedAbsentIdentities);
