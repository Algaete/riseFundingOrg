namespace FundingPlatform.Application.Authentication;

public interface IAuthenticationService
{
    Task<RegistrationResult> RegisterAsync(
        RegistrationInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<bool> VerifyEmailAsync(
        string token,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task ResendVerificationAsync(
        string email,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<LoginResult> LoginAsync(
        LoginInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<RefreshResult> RefreshAsync(
        string refreshToken,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task LogoutAsync(
        string refreshToken,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task LogoutAllAsync(
        Guid publicUserId,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task ForgotPasswordAsync(
        string email,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<PasswordResetResult> ResetPasswordAsync(
        ResetPasswordInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<AuthenticatedUser?> GetCurrentUserAsync(
        Guid publicUserId,
        CancellationToken cancellationToken);

    Task<LoginResult> CompleteMfaChallengeAsync(
        MfaChallengeInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<MfaSetupResult> BeginMfaSetupAsync(
        Guid publicUserId,
        CancellationToken cancellationToken);

    Task<MfaConfirmationResult?> ConfirmMfaSetupAsync(
        Guid publicUserId,
        string code,
        CancellationToken cancellationToken);

    Task<ExternalIdentityCompletionResult> CompleteExternalIdentityAsync(
        ExternalIdentityInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<ExternalIdentityLinkOutcome> LinkExternalIdentityAsync(
        Guid publicUserId,
        ExternalIdentityInput input,
        ClientRequestContext context,
        CancellationToken cancellationToken);

    Task<LoginResult> ExchangeExternalHandoffAsync(
        string handoffCode,
        ClientRequestContext context,
        CancellationToken cancellationToken);
}
