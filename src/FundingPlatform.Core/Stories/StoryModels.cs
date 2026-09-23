namespace FundingPlatform.Core.Stories;

public sealed record StoryContent(string Title, string? Summary, string Body, string Kind, Guid? ProjectId,
    IReadOnlyList<int>? CategoryIds, IReadOnlyList<int>? GoalIds, IReadOnlyList<int>? CountryIds,
    bool ContainsPersonalExperiences = false);
public sealed record StoryWrite(int ExpectedRevision, StoryContent? Content);
public sealed record StoryPublication(int ExpectedRevision, bool Publish, bool RightsConfirmed, bool PersonalConsentConfirmed);
public sealed record Story(Guid Id, Guid OrganizationId, string OrganizationName, string? ProjectTitle,
    string? ProjectSlug, StoryContent Content, byte Status, int Revision, DateTimeOffset UpdatedAtUtc);
public sealed record StoryPage(IReadOnlyList<Story> Items, int TotalCount, int Page);
