using FundingPlatform.Core.Identity;

namespace FundingPlatform.Application.Authentication;

public sealed record ClientRequestContext(
    string? IpAddress,
    string? UserAgent,
    string? CorrelationId);

public sealed record AuthenticatedUser(
    Guid PublicId,
    string Email,
    string DisplayName,
    string PreferredLocale,
    IReadOnlyCollection<string> Roles,
    bool MfaEnabled);

public sealed record AccessSession(
    string AccessToken,
    DateTime ExpiresAtUtc,
    AuthenticatedUser User);

public enum LoginOutcome
{
    Success,
    InvalidCredentials,
    EmailVerificationRequired,
    MfaRequired,
    MfaSetupRequired
}

public sealed record LoginResult(
    LoginOutcome Outcome,
    AccessSession? Session = null,
    string? RefreshToken = null,
    string? MfaChallengeToken = null,
    DateTime? MfaChallengeExpiresAtUtc = null,
    string? MfaSetupToken = null);

public enum RefreshOutcome
{
    Success,
    Invalid,
    Expired,
    ReplayDetected,
    SessionInvalidated,
    Conflict
}

public sealed record RefreshResult(
    RefreshOutcome Outcome,
    AccessSession? Session = null,
    string? RefreshToken = null);

public sealed record MfaSetupResult(
    string SharedKey,
    string AuthenticatorUri);

public sealed record MfaConfirmationResult(
    IReadOnlyCollection<string> RecoveryCodes);

public sealed record SecurityTokenDelivery(
    long UserId,
    string Email,
    string DisplayName,
    string RawToken);

public sealed record PasswordValidationFailure(
    string Code,
    string Description);

public sealed record RegistrationInput(
    string Email,
    string DisplayName,
    string Password,
    string PreferredLocale);

public sealed record LoginInput(
    string Email,
    string Password);

public sealed record MfaChallengeInput(
    string ChallengeToken,
    string Code);

public sealed record ResetPasswordInput(
    string Token,
    string NewPassword);

public sealed record RegistrationResult(
    bool Accepted,
    IReadOnlyCollection<PasswordValidationFailure> ValidationFailures)
{
    public static RegistrationResult GenericAccepted { get; } = new(true, []);
}

public sealed record PasswordResetResult(
    bool Succeeded,
    IReadOnlyCollection<PasswordValidationFailure> ValidationFailures);

public sealed record ExternalIdentityInput(
    string Provider,
    string Issuer,
    string Subject,
    string Email,
    string DisplayName);

public enum ExternalIdentityCompletionOutcome
{
    Success,
    AccountLinkRequired,
    AccountUnavailable,
    InvalidIdentity
}

public sealed record ExternalIdentityCompletionResult(
    ExternalIdentityCompletionOutcome Outcome,
    string? HandoffCode = null);

public enum ExternalIdentityLinkOutcome
{
    Success,
    AlreadyLinkedToCurrentAccount,
    IdentityAlreadyLinked,
    ProviderAlreadyLinked,
    AccountUnavailable,
    InvalidIdentity
}

public sealed class ExternalIdentityRecord
{
    public byte ResultCode { get; set; }

    public long? UserId { get; set; }

    public Guid? PublicId { get; set; }
}

public sealed class ExternalHandoffRecord
{
    public byte ResultCode { get; set; }

    public long? UserId { get; set; }
}

public sealed record RefreshTokenDescriptor(
    long UserId,
    int SecurityVersion,
    bool MfaAuthenticated,
    DateTime? MfaAuthenticatedAtUtc,
    Guid FamilyId,
    byte[] TokenHash,
    Guid JwtId,
    DateTime ExpiresAtUtc,
    byte[]? IpHash,
    string? UserAgent);

public sealed class RefreshRotationRecord
{
    public byte ResultCode { get; set; }

    public long? UserId { get; set; }

    public Guid? PublicId { get; set; }

    public string? Email { get; set; }

    public string? DisplayName { get; set; }

    public int? SecurityVersion { get; set; }

    public bool? TwoFactorEnabled { get; set; }

    public bool? MfaAuthenticated { get; set; }

    public DateTime? MfaAuthenticatedAtUtc { get; set; }

    public Guid? FamilyId { get; set; }
}

public sealed record UserSecuritySnapshot(
    PlatformUser User,
    IReadOnlyCollection<string> Roles);
