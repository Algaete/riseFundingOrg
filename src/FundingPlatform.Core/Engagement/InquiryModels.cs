namespace FundingPlatform.Core.Engagement;

public sealed record InquiryInput(Guid RequestId, string Name, string Email, string? Organization,
    int CountryId, string Topic, string? ServiceCode, string? ProjectReference, string? FundingReference,
    DateOnly? Deadline, string Description, bool ConsentToContact, string? Website = null);
public sealed record InquiryReceipt(Guid RequestId, bool WasReplay);
public sealed record Inquiry(Guid RequestId, InquiryInput Data, string CountryName, byte Status,
    byte NotificationStatus, int Revision, DateTimeOffset CreatedAtUtc);
public sealed record InquiryPage(IReadOnlyList<Inquiry> Items, int TotalCount, int Page);
public sealed record InquiryReview(int ExpectedRevision, byte Status);
