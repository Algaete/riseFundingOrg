using FundingPlatform.Core.Collaboration;

namespace FundingPlatform.Application.Collaboration;

public sealed class ProfessionalProfileService(IProfessionalProfileRepository repository)
{
    public Task<ProfessionalProfile?> GetOwnAsync(Guid userId, CancellationToken token) => repository.GetOwnAsync(userId, token);
    public Task<CollaborationPage<ProfessionalDirectoryEntry>> SearchAsync(Guid userId, ProfessionalDirectoryFilters filters, CancellationToken token)
    {
        if (!CollaborationRules.ValidPage(filters.Page, filters.PageSize) || filters.Query?.Trim().Length > 200 || filters.CountryId is <= 0 || filters.CategoryId is <= 0)
            throw new ArgumentException("Invalid directory filters.", nameof(filters));
        return repository.SearchAsync(userId, filters with { Query = CollaborationRules.Trim(filters.Query) }, token);
    }
    public Task<CollaborationWriteResult> SaveAsync(Guid userId, ProfessionalProfileData input, byte[]? expected, string key, CancellationToken token)
    {
        var data = CollaborationRules.Normalize(input);
        if (CollaborationRules.Validate(data).Count > 0 || !CollaborationRules.ValidKey(key) || expected is not null && expected.Length != 8)
            throw new ArgumentException("Invalid professional profile command.", nameof(input));
        data = data with { Skills = data.Skills!.Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray(),
            CategoryIds = data.CategoryIds!.Distinct().Order().ToArray(), LanguageIds = data.LanguageIds!.Distinct().Order().ToArray() };
        return repository.SaveAsync(userId, data, expected, CollaborationRules.Hash(key), CollaborationRules.Hash(new { operation = "profile-save", userId, data, expected }), token);
    }
}
