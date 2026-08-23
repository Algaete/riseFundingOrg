using System.Net.Mail;
using Dapper;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity.Persistence;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Identity;

public sealed class AdminBootstrapService(
    ISqlConnectionFactory connectionFactory,
    IPasswordHasher<PlatformUser> passwordHasher,
    TimeProvider timeProvider)
{
    public async Task<AdminBootstrapOutcome> BootstrapAsync(
        string email,
        string displayName,
        string password,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeAndValidateEmail(email);
        var normalizedDisplayName = displayName?.Trim() ?? string.Empty;
        if (normalizedDisplayName.Length is < 1 or > 150)
        {
            throw new ArgumentException("Display name must contain between 1 and 150 characters.");
        }

        if (password.Length is < 12 or > 128)
        {
            throw new ArgumentException("Password must contain between 12 and 128 characters.");
        }

        var nowUtc = timeProvider.GetUtcNow().UtcDateTime;
        var user = new PlatformUser
        {
            Email = email.Trim(),
            NormalizedEmail = normalizedEmail,
            DisplayName = normalizedDisplayName,
            SecurityStamp = Guid.NewGuid().ToString("N"),
            SecurityVersion = 1,
            EmailConfirmed = true,
            Status = UserStatus.Active,
            PreferredLocale = "es-CL",
            CreatedAtUtc = nowUtc,
            UpdatedAtUtc = nowUtc
        };
        var passwordHash = passwordHasher.HashPassword(user, password);

        try
        {
            await using var connection = connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var result = await connection.QuerySingleAsync<OperationRecord>(new CommandDefinition(
                "dbo.FundingPlatform_usp_SuperAdmin_Bootstrap",
                new
                {
                    user.Email,
                    user.NormalizedEmail,
                    user.DisplayName,
                    PasswordHash = passwordHash,
                    user.SecurityStamp,
                    user.PreferredLocale,
                    NowUtc = nowUtc
                },
                commandType: System.Data.CommandType.StoredProcedure,
                cancellationToken: cancellationToken));
            return (AdminBootstrapOutcome)result.ResultCode;
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("bootstrap_superadmin", exception.Number, exception);
        }
    }

    private static string NormalizeAndValidateEmail(string? email)
    {
        var value = email?.Trim() ?? string.Empty;
        if (value.Length is < 3 or > 320 ||
            !MailAddress.TryCreate(value, out var parsed) ||
            !string.Equals(parsed.Address, value, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Email is invalid.");
        }

        return value.ToUpperInvariant();
    }
}

public enum AdminBootstrapOutcome : byte
{
    Created = 0,
    AlreadyConfigured = 1,
    EmailAlreadyExists = 2,
    RoleMissing = 3
}
