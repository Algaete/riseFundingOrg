using System.Text;
using Dapper;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Identity.Persistence;

public sealed class DapperUserStore :
    IUserStore<PlatformUser>,
    IUserPasswordStore<PlatformUser>,
    IUserEmailStore<PlatformUser>,
    IUserSecurityStampStore<PlatformUser>,
    IUserLockoutStore<PlatformUser>,
    IUserTwoFactorStore<PlatformUser>,
    IUserAuthenticatorKeyStore<PlatformUser>,
    IUserRoleStore<PlatformUser>
{
    private const string UserColumns = """
        Id, PublicId, Email, NormalizedEmail, DisplayName, PasswordHash,
        SecurityStamp, SecurityVersion, EmailConfirmed, TwoFactorEnabled,
        Status, AccessFailedCount, LockoutEndUtc, PreferredLocale,
        LastLoginAtUtc, CreatedAtUtc, UpdatedAtUtc
        """;

    private const string AliasedUserColumns = """
        users.Id, users.PublicId, users.Email, users.NormalizedEmail, users.DisplayName,
        users.PasswordHash, users.SecurityStamp, users.SecurityVersion, users.EmailConfirmed,
        users.TwoFactorEnabled, users.Status, users.AccessFailedCount, users.LockoutEndUtc,
        users.PreferredLocale, users.LastLoginAtUtc, users.CreatedAtUtc, users.UpdatedAtUtc
        """;

    private readonly ISqlConnectionFactory _connectionFactory;
    private readonly IDataProtector _authenticatorKeyProtector;
    private bool _disposed;

    public DapperUserStore(
        ISqlConnectionFactory connectionFactory,
        IDataProtectionProvider dataProtectionProvider)
    {
        _connectionFactory = connectionFactory;
        _authenticatorKeyProtector = dataProtectionProvider.CreateProtector(
            "FundingPlatform.Identity.AuthenticatorKey.v1");
    }

    public Task<string> GetUserIdAsync(PlatformUser user, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.Id.ToString(System.Globalization.CultureInfo.InvariantCulture));
    }

    public Task<string?> GetUserNameAsync(PlatformUser user, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult<string?>(user.Email);
    }

    public Task SetUserNameAsync(
        PlatformUser user,
        string? userName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.Email = userName ?? string.Empty;
        return Task.CompletedTask;
    }

    public Task<string?> GetNormalizedUserNameAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult<string?>(user.NormalizedEmail);
    }

    public Task SetNormalizedUserNameAsync(
        PlatformUser user,
        string? normalizedName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.NormalizedEmail = normalizedName ?? string.Empty;
        return Task.CompletedTask;
    }

    public async Task<IdentityResult> CreateAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);

        const string sql = """
            INSERT INTO dbo.FundingPlatform_Users
            (
                Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
                SecurityVersion, EmailConfirmed, TwoFactorEnabled, Status,
                AccessFailedCount, LockoutEndUtc, PreferredLocale, LastLoginAtUtc,
                CreatedAtUtc, UpdatedAtUtc
            )
            OUTPUT INSERTED.Id, INSERTED.PublicId, INSERTED.CreatedAtUtc, INSERTED.UpdatedAtUtc
            VALUES
            (
                @Email, @NormalizedEmail, @DisplayName, @PasswordHash, @SecurityStamp,
                @SecurityVersion, @EmailConfirmed, @TwoFactorEnabled, @Status,
                @AccessFailedCount, @LockoutEndUtc, @PreferredLocale, @LastLoginAtUtc,
                @CreatedAtUtc, @UpdatedAtUtc
            );
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var created = await connection.QuerySingleAsync<CreatedUserRecord>(new CommandDefinition(
                sql,
                user,
                cancellationToken: cancellationToken));
            user.Id = created.Id;
            user.PublicId = created.PublicId;
            user.CreatedAtUtc = created.CreatedAtUtc;
            user.UpdatedAtUtc = created.UpdatedAtUtc;
            return IdentityResult.Success;
        }
        catch (SqlException exception) when (exception.Number is 2601 or 2627)
        {
            return IdentityResult.Failed(new IdentityError
            {
                Code = "DuplicateEmail",
                Description = "The account could not be created."
            });
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("create_user", exception.Number, exception);
        }
    }

    public async Task<IdentityResult> UpdateAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);

        const string sql = """
            UPDATE dbo.FundingPlatform_Users
            SET Email = @Email,
                NormalizedEmail = @NormalizedEmail,
                DisplayName = @DisplayName,
                PasswordHash = @PasswordHash,
                SecurityStamp = @SecurityStamp,
                EmailConfirmed = @EmailConfirmed,
                TwoFactorEnabled = @TwoFactorEnabled,
                Status = @Status,
                AccessFailedCount = @AccessFailedCount,
                LockoutEndUtc = @LockoutEndUtc,
                PreferredLocale = @PreferredLocale,
                LastLoginAtUtc = @LastLoginAtUtc,
                UpdatedAtUtc = SYSUTCDATETIME()
            WHERE Id = @Id;
            """;

        var affected = await ExecuteAsync("update_user", sql, user, cancellationToken);
        return affected == 1
            ? IdentityResult.Success
            : IdentityResult.Failed(new IdentityError
            {
                Code = "UserNotFound",
                Description = "The account no longer exists."
            });
    }

    public async Task<IdentityResult> DeleteAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);

        const string sql = """
            UPDATE dbo.FundingPlatform_Users
            SET Status = @DisabledStatus,
                SecurityVersion = SecurityVersion + 1,
                SecurityStamp = @SecurityStamp,
                UpdatedAtUtc = SYSUTCDATETIME()
            WHERE Id = @Id;
            """;

        var affected = await ExecuteAsync(
            "disable_user",
            sql,
            new
            {
                user.Id,
                DisabledStatus = (byte)UserStatus.Disabled,
                SecurityStamp = Guid.NewGuid().ToString("N")
            },
            cancellationToken);

        return affected == 1 ? IdentityResult.Success : IdentityResult.Failed();
    }

    public Task<PlatformUser?> FindByIdAsync(
        string userId,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        return long.TryParse(
            userId,
            System.Globalization.NumberStyles.None,
            System.Globalization.CultureInfo.InvariantCulture,
            out var id)
            ? FindOneAsync("Id = @Value", id, cancellationToken)
            : Task.FromResult<PlatformUser?>(null);
    }

    public Task<PlatformUser?> FindByNameAsync(
        string normalizedUserName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        return FindOneAsync("NormalizedEmail = @Value", normalizedUserName, cancellationToken);
    }

    public Task SetPasswordHashAsync(
        PlatformUser user,
        string? passwordHash,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.PasswordHash = passwordHash;
        return Task.CompletedTask;
    }

    public Task<string?> GetPasswordHashAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.PasswordHash);
    }

    public Task<bool> HasPasswordAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(!string.IsNullOrWhiteSpace(user.PasswordHash));
    }

    public Task SetEmailAsync(
        PlatformUser user,
        string? email,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.Email = email ?? string.Empty;
        return Task.CompletedTask;
    }

    public Task<string?> GetEmailAsync(PlatformUser user, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult<string?>(user.Email);
    }

    public Task<bool> GetEmailConfirmedAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.EmailConfirmed);
    }

    public Task SetEmailConfirmedAsync(
        PlatformUser user,
        bool confirmed,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.EmailConfirmed = confirmed;
        return Task.CompletedTask;
    }

    public Task<PlatformUser?> FindByEmailAsync(
        string normalizedEmail,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        return FindOneAsync("NormalizedEmail = @Value", normalizedEmail, cancellationToken);
    }

    public Task<string?> GetNormalizedEmailAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult<string?>(user.NormalizedEmail);
    }

    public Task SetNormalizedEmailAsync(
        PlatformUser user,
        string? normalizedEmail,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.NormalizedEmail = normalizedEmail ?? string.Empty;
        return Task.CompletedTask;
    }

    public Task SetSecurityStampAsync(
        PlatformUser user,
        string stamp,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.SecurityStamp = stamp;
        return Task.CompletedTask;
    }

    public Task<string?> GetSecurityStampAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult<string?>(user.SecurityStamp);
    }

    public Task<DateTimeOffset?> GetLockoutEndDateAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.LockoutEndUtc is null
            ? (DateTimeOffset?)null
            : new DateTimeOffset(DateTime.SpecifyKind(user.LockoutEndUtc.Value, DateTimeKind.Utc)));
    }

    public Task SetLockoutEndDateAsync(
        PlatformUser user,
        DateTimeOffset? lockoutEnd,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.LockoutEndUtc = lockoutEnd?.UtcDateTime;
        return Task.CompletedTask;
    }

    public Task<int> IncrementAccessFailedCountAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.AccessFailedCount++;
        return Task.FromResult(user.AccessFailedCount);
    }

    public Task ResetAccessFailedCountAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.AccessFailedCount = 0;
        return Task.CompletedTask;
    }

    public Task<int> GetAccessFailedCountAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.AccessFailedCount);
    }

    public Task<bool> GetLockoutEnabledAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(true);
    }

    public Task SetLockoutEnabledAsync(
        PlatformUser user,
        bool enabled,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.CompletedTask;
    }

    public Task SetTwoFactorEnabledAsync(
        PlatformUser user,
        bool enabled,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        user.TwoFactorEnabled = enabled;
        return Task.CompletedTask;
    }

    public Task<bool> GetTwoFactorEnabledAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        return Task.FromResult(user.TwoFactorEnabled);
    }

    public async Task SetAuthenticatorKeyAsync(
        PlatformUser user,
        string key,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(key);

        const string sql = """
            UPDATE dbo.FundingPlatform_UserAuthenticatorKeys
            SET EncryptedKey = @EncryptedKey,
                ConfirmedAtUtc = NULL,
                UpdatedAtUtc = @NowUtc
            WHERE UserId = @UserId;

            IF @@ROWCOUNT = 0
            BEGIN
                INSERT INTO dbo.FundingPlatform_UserAuthenticatorKeys
                (UserId, EncryptedKey, ConfirmedAtUtc, UpdatedAtUtc)
                VALUES (@UserId, @EncryptedKey, NULL, @NowUtc);
            END;
            """;

        var encrypted = _authenticatorKeyProtector.Protect(Encoding.UTF8.GetBytes(key));
        await ExecuteAsync(
            "set_authenticator_key",
            sql,
            new { UserId = user.Id, EncryptedKey = encrypted, NowUtc = DateTime.UtcNow },
            cancellationToken);
    }

    public async Task<string?> GetAuthenticatorKeyAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);

        const string sql = """
            SELECT EncryptedKey
            FROM dbo.FundingPlatform_UserAuthenticatorKeys
            WHERE UserId = @UserId;
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var encrypted = await connection.QuerySingleOrDefaultAsync<byte[]>(new CommandDefinition(
                sql,
                new { UserId = user.Id },
                cancellationToken: cancellationToken));
            return encrypted is null
                ? null
                : Encoding.UTF8.GetString(_authenticatorKeyProtector.Unprotect(encrypted));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(
                "get_authenticator_key",
                exception.Number,
                exception);
        }
    }

    public Task AddToRoleAsync(
        PlatformUser user,
        string roleName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(roleName);

        const string sql = """
            INSERT INTO dbo.FundingPlatform_UserRoles (UserId, RoleId, CreatedAtUtc)
            SELECT @UserId, roles.Id, SYSUTCDATETIME()
            FROM dbo.FundingPlatform_Roles AS roles
            WHERE roles.NormalizedName = @NormalizedRoleName
              AND NOT EXISTS
              (
                  SELECT 1
                  FROM dbo.FundingPlatform_UserRoles AS existing
                  WHERE existing.UserId = @UserId
                    AND existing.RoleId = roles.Id
              );
            """;

        return ExecuteWithoutResultAsync(
            "add_user_role",
            sql,
            new { UserId = user.Id, NormalizedRoleName = roleName.ToUpperInvariant() },
            cancellationToken);
    }

    public Task RemoveFromRoleAsync(
        PlatformUser user,
        string roleName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(roleName);

        const string sql = """
            DELETE userRoles
            FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles
                ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId
              AND roles.NormalizedName = @NormalizedRoleName;
            """;

        return ExecuteWithoutResultAsync(
            "remove_user_role",
            sql,
            new { UserId = user.Id, NormalizedRoleName = roleName.ToUpperInvariant() },
            cancellationToken);
    }

    public async Task<IList<string>> GetRolesAsync(
        PlatformUser user,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);

        const string sql = """
            SELECT roles.Name
            FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles
                ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId
            ORDER BY roles.Id;
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var roles = await connection.QueryAsync<string>(new CommandDefinition(
                sql,
                new { UserId = user.Id },
                cancellationToken: cancellationToken));
            return roles.AsList();
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("get_user_roles", exception.Number, exception);
        }
    }

    public async Task<bool> IsInRoleAsync(
        PlatformUser user,
        string roleName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentNullException.ThrowIfNull(user);
        ArgumentException.ThrowIfNullOrWhiteSpace(roleName);

        const string sql = """
            SELECT CONVERT(BIT, CASE WHEN EXISTS
            (
                SELECT 1
                FROM dbo.FundingPlatform_UserRoles AS userRoles
                INNER JOIN dbo.FundingPlatform_Roles AS roles
                    ON roles.Id = userRoles.RoleId
                WHERE userRoles.UserId = @UserId
                  AND roles.NormalizedName = @NormalizedRoleName
            ) THEN 1 ELSE 0 END);
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.QuerySingleAsync<bool>(new CommandDefinition(
                sql,
                new { UserId = user.Id, NormalizedRoleName = roleName.ToUpperInvariant() },
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("is_user_in_role", exception.Number, exception);
        }
    }

    public async Task<IList<PlatformUser>> GetUsersInRoleAsync(
        string roleName,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        ArgumentException.ThrowIfNullOrWhiteSpace(roleName);

        var sql = $"""
            SELECT {AliasedUserColumns}
            FROM dbo.FundingPlatform_Users AS users
            INNER JOIN dbo.FundingPlatform_UserRoles AS userRoles
                ON userRoles.UserId = users.Id
            INNER JOIN dbo.FundingPlatform_Roles AS roles
                ON roles.Id = userRoles.RoleId
            WHERE roles.NormalizedName = @NormalizedRoleName
            ORDER BY users.Id;
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var users = await connection.QueryAsync<PlatformUser>(new CommandDefinition(
                sql,
                new { NormalizedRoleName = roleName.ToUpperInvariant() },
                cancellationToken: cancellationToken));
            return users.AsList();
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("get_users_in_role", exception.Number, exception);
        }
    }

    public void Dispose()
    {
        _disposed = true;
    }

    private async Task<PlatformUser?> FindOneAsync(
        string predicate,
        object value,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT {UserColumns}
            FROM dbo.FundingPlatform_Users
            WHERE {predicate};
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.QuerySingleOrDefaultAsync<PlatformUser>(new CommandDefinition(
                sql,
                new { Value = value },
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("find_user", exception.Number, exception);
        }
    }

    private async Task<int> ExecuteAsync(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.ExecuteAsync(new CommandDefinition(
                sql,
                parameters,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task ExecuteWithoutResultAsync(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        _ = await ExecuteAsync(operation, sql, parameters, cancellationToken);
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private sealed record CreatedUserRecord(
        long Id,
        Guid PublicId,
        DateTime CreatedAtUtc,
        DateTime UpdatedAtUtc);
}
