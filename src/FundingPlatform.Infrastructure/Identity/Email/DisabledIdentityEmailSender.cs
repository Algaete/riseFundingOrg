using FundingPlatform.Application.Authentication;

namespace FundingPlatform.Infrastructure.Identity.Email;

public sealed class DisabledIdentityEmailSender : IIdentityEmailSender
{
    private const string DisabledMessage = "identity_email_delivery_disabled";

    public Task SendVerificationAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken) =>
        Task.FromException(new InvalidOperationException(DisabledMessage));

    public Task SendPasswordResetAsync(
        string email,
        string displayName,
        string rawToken,
        CancellationToken cancellationToken) =>
        Task.FromException(new InvalidOperationException(DisabledMessage));
}
