using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Infrastructure.Persistence.Sql;

namespace FundingPlatform.Infrastructure.Persistence.Collaboration;

public sealed class SqlProfessionalProfileRepository(ISqlConnectionFactory connectionFactory)
    : SqlCollaborationRepository(connectionFactory), IProfessionalProfileRepository
{
    public Task<ProfessionalProfile?> GetOwnAsync(Guid userId, CancellationToken token) => ReadAsync<ProfessionalProfile>(
        "ProfessionalProfile_GetOwn", new { UserPublicId = userId }, token);
    public async Task<CollaborationPage<ProfessionalDirectoryEntry>> SearchAsync(Guid userId, ProfessionalDirectoryFilters filters, CancellationToken token) =>
        await ReadAsync<CollaborationPage<ProfessionalDirectoryEntry>>("ProfessionalProfile_Search", new { UserPublicId = userId,
            filters.Query, filters.CountryId, filters.CategoryId, filters.Page, filters.PageSize }, token)
        ?? throw new InvalidOperationException("Missing directory response.");
    public Task<CollaborationWriteResult> SaveAsync(Guid userId, ProfessionalProfileData data, byte[]? expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken token) => WriteAsync("ProfessionalProfile_Save", new
        {
            UserPublicId = userId, DataJson = Json(data), ExpectedRowVersion = expectedRowVersion, KeyHash = keyHash, RequestHash = requestHash
        }, token);
}
