using System.Data;
using System.Net.Mail;
using Dapper;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity.Cryptography;
using FundingPlatform.Infrastructure.Identity.Persistence;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Identity;

/// <summary>
/// Provides the deliberately narrow, local-operator surface used to inspect global
/// administrators and grant the SuperAdmin role to an existing account.
/// </summary>
public sealed class GlobalRoleAdministrationService(
    ISqlConnectionFactory connectionFactory,
    TimeProvider timeProvider)
{
    private const string LocalPromotionReason = "owner_authorized_local_promotion";

    public async Task<IReadOnlyCollection<GlobalAdministratorSummary>> ListAdministratorsAsync(
        CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var records = await connection.QueryAsync<GlobalAdministratorRecord>(new CommandDefinition(
                "dbo.FundingPlatform_usp_GlobalRole_ListAdministrators",
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));
            return records.Select(record => new GlobalAdministratorSummary(
                    MaskEmail(record.Email),
                    record.RoleName,
                    record.Status,
                    record.EmailConfirmed,
                    record.TwoFactorEnabled,
                    record.GrantedAtUtc))
                .ToArray();
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(
                "list_global_administrators",
                exception.Number,
                exception);
        }
    }

    public async Task<GrantSuperAdminResult> GrantSuperAdminAsync(
        string email,
        CancellationToken cancellationToken)
    {
        var normalizedEmail = NormalizeAndValidateEmail(email);

        try
        {
            await using var connection = connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            var record = await connection.QuerySingleAsync<GrantSuperAdminRecord>(new CommandDefinition(
                "dbo.FundingPlatform_usp_GlobalRole_GrantSuperAdmin",
                new
                {
                    NormalizedEmail = normalizedEmail,
                    ReasonCode = LocalPromotionReason,
                    SecurityStamp = SecureTokenGenerator.GenerateOpaqueToken(32),
                    OperationId = Guid.NewGuid(),
                    NowUtc = timeProvider.GetUtcNow().UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                cancellationToken: cancellationToken));

            return new GrantSuperAdminResult(
                (GrantSuperAdminOutcome)record.ResultCode,
                MaskEmail(record.Email),
                record.SecurityVersion,
                record.TwoFactorEnabled,
                record.GrantedAtUtc);
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException(
                "grant_superadmin",
                exception.Number,
                exception);
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

    private static string MaskEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return "(not available)";
        }

        var separator = email.LastIndexOf('@');
        if (separator <= 0 || separator == email.Length - 1)
        {
            return "(redacted)";
        }

        var localPart = email[..separator];
        var maskedLocalPart = localPart.Length == 1
            ? $"{localPart[0]}***"
            : $"{localPart[0]}***{localPart[^1]}";
        return $"{maskedLocalPart}@{email[(separator + 1)..]}";
    }
}

public sealed record GlobalAdministratorSummary(
    string MaskedEmail,
    string RoleName,
    UserStatus Status,
    bool EmailConfirmed,
    bool TwoFactorEnabled,
    DateTime GrantedAtUtc);

public sealed record GrantSuperAdminResult(
    GrantSuperAdminOutcome Outcome,
    string MaskedEmail,
    int? SecurityVersion,
    bool? TwoFactorEnabled,
    DateTime? GrantedAtUtc);

internal sealed class GlobalAdministratorRecord
{
    public string Email { get; set; } = string.Empty;

    public string RoleName { get; set; } = string.Empty;

    public UserStatus Status { get; set; }

    public bool EmailConfirmed { get; set; }

    public bool TwoFactorEnabled { get; set; }

    public DateTime GrantedAtUtc { get; set; }
}

public enum GrantSuperAdminOutcome : byte
{
    Granted = 0,
    AlreadyGranted = 1,
    UserNotFound = 2,
    UserNotEligible = 3,
    RoleMissing = 4
}

internal sealed class GrantSuperAdminRecord
{
    public byte ResultCode { get; set; }

    public string? Email { get; set; }

    public int? SecurityVersion { get; set; }

    public bool? TwoFactorEnabled { get; set; }

    public DateTime? GrantedAtUtc { get; set; }
}
