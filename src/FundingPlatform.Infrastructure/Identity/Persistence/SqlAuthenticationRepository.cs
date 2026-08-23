using System.Data;
using Dapper;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Identity.Persistence;

public sealed class SqlAuthenticationRepository
{
    private const string UserColumns = """
        Id, PublicId, Email, NormalizedEmail, DisplayName, PasswordHash,
        SecurityStamp, SecurityVersion, EmailConfirmed, TwoFactorEnabled,
        Status, AccessFailedCount, LockoutEndUtc, PreferredLocale,
        LastLoginAtUtc, CreatedAtUtc, UpdatedAtUtc
        """;

    private readonly ISqlConnectionFactory _connectionFactory;

    public SqlAuthenticationRepository(ISqlConnectionFactory connectionFactory)
    {
        _connectionFactory = connectionFactory;
    }

    public async Task<byte> RegisterAsync(
        PlatformUser user,
        byte[] verificationTokenHash,
        DateTime verificationExpiresAtUtc,
        byte[]? ipHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var record = await QuerySingleStoredProcedureAsync<OperationRecord>(
            "register_user",
            "dbo.FundingPlatform_usp_User_Register",
            new
            {
                user.Email,
                user.NormalizedEmail,
                user.DisplayName,
                user.PasswordHash,
                user.SecurityStamp,
                user.PreferredLocale,
                TokenHash = verificationTokenHash,
                TokenExpiresAtUtc = verificationExpiresAtUtc,
                RequestedIpHash = ipHash,
                NowUtc = nowUtc
            },
            cancellationToken);
        return record.ResultCode;
    }

    public Task<SecurityTokenIssueRecord> IssueSecurityTokenAsync(
        string normalizedEmail,
        byte purpose,
        byte[] tokenHash,
        DateTime expiresAtUtc,
        byte[]? ipHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return QuerySingleStoredProcedureAsync<SecurityTokenIssueRecord>(
            "issue_security_token",
            "dbo.FundingPlatform_usp_UserSecurityToken_Issue",
            new
            {
                NormalizedEmail = normalizedEmail,
                Purpose = purpose,
                TokenHash = tokenHash,
                ExpiresAtUtc = expiresAtUtc,
                RequestedIpHash = ipHash,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public async Task<bool> VerifyEmailAsync(
        byte[] tokenHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var record = await QuerySingleStoredProcedureAsync<OperationRecord>(
            "verify_email",
            "dbo.FundingPlatform_usp_User_VerifyEmail",
            new { TokenHash = tokenHash, NowUtc = nowUtc },
            cancellationToken);
        return record.ResultCode == 0;
    }

    public async Task<bool> ResetPasswordAsync(
        byte[] tokenHash,
        string passwordHash,
        string securityStamp,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        var record = await QuerySingleStoredProcedureAsync<OperationRecord>(
            "reset_password",
            "dbo.FundingPlatform_usp_User_ResetPassword",
            new
            {
                TokenHash = tokenHash,
                PasswordHash = passwordHash,
                SecurityStamp = securityStamp,
                NowUtc = nowUtc
            },
            cancellationToken);
        return record.ResultCode == 0;
    }

    public Task<PlatformUser?> FindByNormalizedEmailAsync(
        string normalizedEmail,
        CancellationToken cancellationToken)
    {
        return FindUserAsync("NormalizedEmail = @Value", normalizedEmail, cancellationToken);
    }

    public Task<PlatformUser?> FindByPublicIdAsync(
        Guid publicId,
        CancellationToken cancellationToken)
    {
        return FindUserAsync("PublicId = @Value", publicId, cancellationToken);
    }

    public Task<PlatformUser?> FindByIdAsync(long id, CancellationToken cancellationToken)
    {
        return FindUserAsync("Id = @Value", id, cancellationToken);
    }

    public async Task<IReadOnlyCollection<string>> GetRolesAsync(
        long userId,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT roles.Name
            FROM dbo.FundingPlatform_UserRoles AS userRoles
            INNER JOIN dbo.FundingPlatform_Roles AS roles
                ON roles.Id = userRoles.RoleId
            WHERE userRoles.UserId = @UserId
            ORDER BY roles.Id;
            """;

        return await QueryAsync<string>(
            "get_roles",
            sql,
            new { UserId = userId },
            cancellationToken);
    }

    public async Task<LoginFailureRecord> RecordFailedLoginAsync(
        long userId,
        int maximumAttempts,
        TimeSpan lockoutDuration,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE dbo.FundingPlatform_Users WITH (UPDLOCK)
            SET AccessFailedCount =
                    CASE WHEN AccessFailedCount + 1 >= @MaximumAttempts
                         THEN 0 ELSE AccessFailedCount + 1 END,
                LockoutEndUtc =
                    CASE WHEN AccessFailedCount + 1 >= @MaximumAttempts
                         THEN @LockoutEndUtc ELSE LockoutEndUtc END,
                UpdatedAtUtc = @NowUtc
            OUTPUT INSERTED.AccessFailedCount, INSERTED.LockoutEndUtc
            WHERE Id = @UserId;
            """;

        return await QuerySingleAsync<LoginFailureRecord>(
            "record_failed_login",
            sql,
            new
            {
                UserId = userId,
                MaximumAttempts = maximumAttempts,
                LockoutEndUtc = nowUtc.Add(lockoutDuration),
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task RecordSuccessfulLoginAsync(
        long userId,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE dbo.FundingPlatform_Users
            SET AccessFailedCount = 0,
                LockoutEndUtc = NULL,
                LastLoginAtUtc = @NowUtc,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @UserId;
            """;

        return ExecuteAsync(
            "record_successful_login",
            sql,
            new { UserId = userId, NowUtc = nowUtc },
            cancellationToken);
    }

    public Task CreateRefreshTokenAsync(
        RefreshTokenDescriptor token,
        DateTime createdAtUtc,
        CancellationToken cancellationToken)
    {
        return ExecuteStoredProcedureAsync(
            "create_refresh_token",
            "dbo.FundingPlatform_usp_RefreshToken_Create",
            new
            {
                token.UserId,
                token.SecurityVersion,
                token.MfaAuthenticated,
                token.MfaAuthenticatedAtUtc,
                token.FamilyId,
                token.TokenHash,
                token.JwtId,
                token.ExpiresAtUtc,
                CreatedAtUtc = createdAtUtc,
                CreatedIpHash = token.IpHash,
                token.UserAgent
            },
            cancellationToken);
    }

    public Task<ExternalIdentityRecord> CompleteExternalIdentityAsync(
        ExternalIdentityInput identity,
        string normalizedEmail,
        string passwordHash,
        string securityStamp,
        byte[] handoffTokenHash,
        DateTime handoffExpiresAtUtc,
        byte[]? ipHash,
        string? userAgent,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return QuerySingleStoredProcedureAsync<ExternalIdentityRecord>(
            "complete_external_identity",
            "dbo.FundingPlatform_usp_ExternalIdentity_Complete",
            new
            {
                identity.Provider,
                identity.Issuer,
                ProviderSubject = identity.Subject,
                identity.Email,
                NormalizedEmail = normalizedEmail,
                identity.DisplayName,
                PasswordHash = passwordHash,
                SecurityStamp = securityStamp,
                HandoffTokenHash = handoffTokenHash,
                HandoffExpiresAtUtc = handoffExpiresAtUtc,
                CreatedIpHash = ipHash,
                UserAgent = userAgent,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task<ExternalIdentityRecord> LinkExternalIdentityAsync(
        Guid userPublicId,
        ExternalIdentityInput identity,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return QuerySingleStoredProcedureAsync<ExternalIdentityRecord>(
            "link_external_identity",
            "dbo.FundingPlatform_usp_ExternalIdentity_Link",
            new
            {
                UserPublicId = userPublicId,
                identity.Provider,
                identity.Issuer,
                ProviderSubject = identity.Subject,
                identity.Email,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task<ExternalHandoffRecord> ConsumeExternalHandoffAsync(
        byte[] tokenHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return QuerySingleStoredProcedureAsync<ExternalHandoffRecord>(
            "consume_external_handoff",
            "dbo.FundingPlatform_usp_ExternalAuthHandoff_Consume",
            new { TokenHash = tokenHash, NowUtc = nowUtc },
            cancellationToken);
    }

    public Task<RefreshRotationRecord> RotateRefreshTokenAsync(
        byte[] currentTokenHash,
        byte[] replacementTokenHash,
        Guid replacementJwtId,
        DateTime replacementExpiresAtUtc,
        byte[]? ipHash,
        string? userAgent,
        DateTime nowUtc,
        DateTime graceUntilUtc,
        CancellationToken cancellationToken)
    {
        return QuerySingleStoredProcedureAsync<RefreshRotationRecord>(
            "rotate_refresh_token",
            "dbo.FundingPlatform_usp_RefreshToken_Rotate",
            new
            {
                CurrentTokenHash = currentTokenHash,
                ReplacementTokenHash = replacementTokenHash,
                ReplacementJwtId = replacementJwtId,
                ReplacementExpiresAtUtc = replacementExpiresAtUtc,
                CreatedIpHash = ipHash,
                UserAgent = userAgent,
                NowUtc = nowUtc,
                GraceUntilUtc = graceUntilUtc
            },
            cancellationToken);
    }

    public Task RevokeRefreshFamilyAsync(
        byte[] tokenHash,
        byte reason,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return ExecuteStoredProcedureAsync(
            "revoke_refresh_family",
            "dbo.FundingPlatform_usp_RefreshToken_RevokeFamily",
            new { TokenHash = tokenHash, Reason = reason, NowUtc = nowUtc },
            cancellationToken);
    }

    public Task InvalidateSessionsAsync(
        long userId,
        string securityStamp,
        byte reason,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        return ExecuteStoredProcedureAsync(
            "invalidate_sessions",
            "dbo.FundingPlatform_usp_User_InvalidateSessions",
            new
            {
                UserId = userId,
                SecurityStamp = securityStamp,
                Reason = reason,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task CreateMfaChallengeAsync(
        long userId,
        int securityVersion,
        byte[] tokenHash,
        DateTime expiresAtUtc,
        short maxAttempts,
        byte[]? ipHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;

            UPDATE dbo.FundingPlatform_UserMfaChallenges
            SET ConsumedAtUtc = @NowUtc
            WHERE UserId = @UserId
              AND Purpose = 0
              AND ConsumedAtUtc IS NULL;

            INSERT INTO dbo.FundingPlatform_UserMfaChallenges
            (
                UserId, SecurityVersion, Purpose, TokenHash, ExpiresAtUtc,
                AttemptCount, MaxAttempts, CreatedIpHash, CreatedAtUtc
            )
            VALUES
            (
                @UserId, @SecurityVersion, 0, @TokenHash, @ExpiresAtUtc,
                0, @MaxAttempts, @IpHash, @NowUtc
            );

            COMMIT TRANSACTION;
            """;

        return ExecuteAsync(
            "create_mfa_challenge",
            sql,
            new
            {
                UserId = userId,
                SecurityVersion = securityVersion,
                TokenHash = tokenHash,
                ExpiresAtUtc = expiresAtUtc,
                MaxAttempts = maxAttempts,
                IpHash = ipHash,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task<MfaChallengeRecord?> GetMfaChallengeAsync(
        byte[] tokenHash,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SELECT
                challenges.Id,
                challenges.UserId,
                challenges.SecurityVersion,
                challenges.ExpiresAtUtc,
                challenges.AttemptCount,
                challenges.MaxAttempts,
                challenges.ConsumedAtUtc
            FROM dbo.FundingPlatform_UserMfaChallenges AS challenges
            WHERE challenges.TokenHash = @TokenHash
              AND challenges.Purpose = 0;
            """;

        return QuerySingleOrDefaultAsync<MfaChallengeRecord>(
            "get_mfa_challenge",
            sql,
            new { TokenHash = tokenHash },
            cancellationToken);
    }

    public async Task<bool> CompleteMfaChallengeAttemptAsync(
        long challengeId,
        bool succeeded,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE dbo.FundingPlatform_UserMfaChallenges WITH (UPDLOCK)
            SET AttemptCount = CASE WHEN @Succeeded = 1 THEN AttemptCount ELSE AttemptCount + 1 END,
                ConsumedAtUtc = CASE
                    WHEN @Succeeded = 1 OR AttemptCount + 1 >= MaxAttempts
                    THEN @NowUtc ELSE NULL END
            WHERE Id = @ChallengeId
              AND ConsumedAtUtc IS NULL
              AND ExpiresAtUtc > @NowUtc
              AND AttemptCount < MaxAttempts;

            SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END);
            """;

        return await QuerySingleAsync<bool>(
            "complete_mfa_challenge_attempt",
            sql,
            new { ChallengeId = challengeId, Succeeded = succeeded, NowUtc = nowUtc },
            cancellationToken);
    }

    public Task MarkMfaConfirmedAsync(
        long userId,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            SET XACT_ABORT ON;
            BEGIN TRANSACTION;

            UPDATE dbo.FundingPlatform_UserAuthenticatorKeys
            SET ConfirmedAtUtc = @NowUtc,
                UpdatedAtUtc = @NowUtc
            WHERE UserId = @UserId;

            IF @@ROWCOUNT <> 1
                THROW 51010, 'Authenticator key is missing.', 1;

            UPDATE dbo.FundingPlatform_Users
            SET TwoFactorEnabled = 1,
                UpdatedAtUtc = @NowUtc
            WHERE Id = @UserId;

            COMMIT TRANSACTION;
            """;

        return ExecuteAsync(
            "confirm_mfa",
            sql,
            new { UserId = userId, NowUtc = nowUtc },
            cancellationToken);
    }

    public async Task ReplaceRecoveryCodesAsync(
        long userId,
        string hashKeyVersion,
        IReadOnlyCollection<byte[]> codeHashes,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string deleteSql = """
            DELETE FROM dbo.FundingPlatform_UserRecoveryCodes
            WHERE UserId = @UserId
              AND ConsumedAtUtc IS NULL;
            """;
        const string insertSql = """
            INSERT INTO dbo.FundingPlatform_UserRecoveryCodes
            (UserId, CodeHash, HashKeyVersion, CreatedAtUtc)
            VALUES (@UserId, @CodeHash, @HashKeyVersion, @NowUtc);
            """;

        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            await connection.ExecuteAsync(new CommandDefinition(
                deleteSql,
                new { UserId = userId },
                transaction,
                cancellationToken: cancellationToken));

            foreach (var codeHash in codeHashes)
            {
                await connection.ExecuteAsync(new CommandDefinition(
                    insertSql,
                    new
                    {
                        UserId = userId,
                        CodeHash = codeHash,
                        HashKeyVersion = hashKeyVersion,
                        NowUtc = nowUtc
                    },
                    transaction,
                    cancellationToken: cancellationToken));
            }

            await transaction.CommitAsync(cancellationToken);
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(
                "replace_recovery_codes",
                exception.Number,
                exception);
        }
    }

    public async Task<bool> TryConsumeRecoveryCodeAsync(
        long userId,
        string hashKeyVersion,
        byte[] codeHash,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            UPDATE dbo.FundingPlatform_UserRecoveryCodes WITH (UPDLOCK)
            SET ConsumedAtUtc = @NowUtc
            WHERE UserId = @UserId
              AND HashKeyVersion = @HashKeyVersion
              AND CodeHash = @CodeHash
              AND ConsumedAtUtc IS NULL;

            SELECT CONVERT(BIT, CASE WHEN @@ROWCOUNT = 1 THEN 1 ELSE 0 END);
            """;

        return await QuerySingleAsync<bool>(
            "consume_recovery_code",
            sql,
            new
            {
                UserId = userId,
                HashKeyVersion = hashKeyVersion,
                CodeHash = codeHash,
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    public Task WriteAuthenticationEventAsync(
        long? userId,
        byte eventType,
        byte outcome,
        string? reasonCode,
        byte[]? ipHash,
        string? userAgent,
        string? correlationId,
        DateTime nowUtc,
        CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO dbo.FundingPlatform_AuthenticationEvents
            (
                UserId, EventType, Outcome, ReasonCode, IpHash,
                UserAgent, CorrelationId, CreatedAtUtc
            )
            VALUES
            (
                @UserId, @EventType, @Outcome, @ReasonCode, @IpHash,
                @UserAgent, @CorrelationId, @NowUtc
            );
            """;

        return ExecuteAsync(
            "write_authentication_event",
            sql,
            new
            {
                UserId = userId,
                EventType = eventType,
                Outcome = outcome,
                ReasonCode = Truncate(reasonCode, 50),
                IpHash = ipHash,
                UserAgent = Truncate(userAgent, 300),
                CorrelationId = Truncate(correlationId, 100),
                NowUtc = nowUtc
            },
            cancellationToken);
    }

    private async Task<PlatformUser?> FindUserAsync(
        string predicate,
        object value,
        CancellationToken cancellationToken)
    {
        var sql = $"""
            SELECT {UserColumns}
            FROM dbo.FundingPlatform_Users
            WHERE {predicate};
            """;

        return await QuerySingleOrDefaultAsync<PlatformUser>(
            "find_user",
            sql,
            new { Value = value },
            cancellationToken);
    }

    private async Task<T> QuerySingleStoredProcedureAsync<T>(
        string operation,
        string procedure,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.QuerySingleAsync<T>(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task ExecuteStoredProcedureAsync(
        string operation,
        string procedure,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            _ = await connection.ExecuteAsync(new CommandDefinition(
                procedure,
                parameters,
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task<T> QuerySingleAsync<T>(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.QuerySingleAsync<T>(new CommandDefinition(
                sql,
                parameters,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task<T?> QuerySingleOrDefaultAsync<T>(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            return await connection.QuerySingleOrDefaultAsync<T>(new CommandDefinition(
                sql,
                parameters,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task<IReadOnlyCollection<T>> QueryAsync<T>(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var values = await connection.QueryAsync<T>(new CommandDefinition(
                sql,
                parameters,
                cancellationToken: cancellationToken));
            return values.AsList();
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private async Task ExecuteAsync(
        string operation,
        string sql,
        object parameters,
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = _connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            _ = await connection.ExecuteAsync(new CommandDefinition(
                sql,
                parameters,
                cancellationToken: cancellationToken));
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(operation, exception.Number, exception);
        }
    }

    private static string? Truncate(string? value, int maximumLength)
    {
        return string.IsNullOrEmpty(value) || value.Length <= maximumLength
            ? value
            : value[..maximumLength];
    }
}

public sealed class OperationRecord
{
    public byte ResultCode { get; set; }

    public long? UserId { get; set; }

    public Guid? PublicId { get; set; }
}

public sealed record SecurityTokenIssueRecord(
    byte ResultCode,
    long? UserId,
    string? Email,
    string? DisplayName);

public sealed record LoginFailureRecord(
    int AccessFailedCount,
    DateTime? LockoutEndUtc);

public sealed record MfaChallengeRecord(
    long Id,
    long UserId,
    int SecurityVersion,
    DateTime ExpiresAtUtc,
    short AttemptCount,
    short MaxAttempts,
    DateTime? ConsumedAtUtc);
