namespace FundingPlatform.Core.Donations;

// Future boundary only: not registered, persisted or exposed by any payment endpoint.
// A project donation must be validated against its owning organization at activation.
public abstract record DonationRecipient(Guid OrganizationId)
{
    public sealed record Organization(Guid Id) : DonationRecipient(Id);
    public sealed record Project(Guid OwningOrganizationId, Guid ProjectId) : DonationRecipient(OwningOrganizationId);
}

public enum DonationTransactionStatus { Pending, Confirmed, Failed, Refunded }

// Provider-neutral future ledger contract. Fee and net are unknown until settlement;
// there is deliberately no default commission or provider integration in the MVP.
public sealed record DonationTransactionDesign(
    Guid Id, DonationRecipient Recipient, Guid DonorReference, decimal Amount,
    string Currency, DateTimeOffset CreatedAtUtc, string? PaymentProvider,
    string? PaymentMethod, DonationTransactionStatus Status, decimal? PlatformFee,
    decimal? OrganizationNetAmount, string? ProviderTransactionId, string? ReceiptReference);
