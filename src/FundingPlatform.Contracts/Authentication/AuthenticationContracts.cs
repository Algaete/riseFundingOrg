namespace FundingPlatform.Contracts.Authentication;

public sealed record RegisterRequest(
    string Email,
    string DisplayName,
    string Password,
    string PreferredLocale = "es-CL");

public sealed record EmailRequest(string Email);

public sealed record VerifyEmailRequest(string Token);

public sealed record LoginRequest(string Email, string Password);

public sealed record MfaChallengeRequest(string ChallengeToken, string Code);

public sealed record ResetPasswordRequest(string Token, string NewPassword);

public sealed record MfaCodeRequest(string Code);

public sealed record AcceptedResponse(string Message);

public sealed record AuthenticatedUserResponse(
    Guid PublicId,
    string Email,
    string DisplayName,
    string PreferredLocale,
    IReadOnlyCollection<string> Roles,
    bool MfaEnabled);

public sealed record AuthenticationResponse(
    string Status,
    string? AccessToken,
    DateTime? AccessTokenExpiresAtUtc,
    AuthenticatedUserResponse? User,
    string? MfaChallengeToken = null,
    DateTime? MfaChallengeExpiresAtUtc = null,
    string? MfaSetupToken = null);

public sealed record MfaSetupResponse(
    string SharedKey,
    string AuthenticatorUri);

public sealed record MfaConfirmationResponse(
    IReadOnlyCollection<string> RecoveryCodes);

public sealed record ExternalProviderResponse(
    string Code,
    string DisplayName,
    bool Enabled);

public sealed record ExternalHandoffExchangeRequest(string Code);

public sealed record ExternalLinkIntentResponse(string StartUrl);
