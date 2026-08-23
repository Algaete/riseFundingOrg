namespace FundingPlatform.Application.Authentication;

public interface IIdentityEmailSender
{
    Task SendVerificationAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken);

    Task SendPasswordResetAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken);
}
