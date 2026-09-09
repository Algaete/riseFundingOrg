using FundingPlatform.Application.Collaboration;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Infrastructure.Persistence.Sql;

namespace FundingPlatform.Infrastructure.Persistence.Collaboration;

public sealed class SqlConsortiumRepository(ISqlConnectionFactory connectionFactory) : SqlCollaborationRepository(connectionFactory), IConsortiumRepository
{
    public async Task<CollaborationPage<ConsortiumSummary>> ListAsync(Guid userId, int page, int pageSize, CancellationToken token) =>
        await ReadAsync<CollaborationPage<ConsortiumSummary>>("Consortium_List", new { UserPublicId = userId, Page = page, PageSize = pageSize }, token)
        ?? throw new InvalidOperationException("Missing consortium list response.");
    public Task<ConsortiumDetails?> GetAsync(Guid userId, Guid consortiumId, CancellationToken token) =>
        ReadAsync<ConsortiumDetails>("Consortium_Get", new { UserPublicId = userId, ConsortiumPublicId = consortiumId }, token);
    public Task<CollaborationWriteResult> CreateAsync(Guid userId, ConsortiumCreateData data, byte[] keyHash, byte[] requestHash, CancellationToken token) =>
        WriteAsync("Consortium_Create", new { UserPublicId = userId, ProjectPublicId = data.ProjectId, data.Name, data.Summary, KeyHash = keyHash, RequestHash = requestHash }, token);
    public Task<CollaborationWriteResult> UpdateAsync(Guid userId, Guid consortiumId, ConsortiumUpdateData data, byte[] expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken token) => WriteAsync("Consortium_Update", new { UserPublicId = userId,
            ConsortiumPublicId = consortiumId, data.Name, data.Summary, Status = (byte)data.Status, ExpectedRowVersion = expectedRowVersion, KeyHash = keyHash, RequestHash = requestHash }, token);
    public Task<CollaborationWriteResult> InviteAsync(Guid userId, Guid consortiumId, ConsortiumInvitationData data, byte[] expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken token) => WriteAsync("Consortium_Invite", new { UserPublicId = userId,
            ConsortiumPublicId = consortiumId, Kind = (byte)data.Kind, TargetPublicId = data.TargetId, data.Contribution, data.Message,
            ExpectedRowVersion = expectedRowVersion, KeyHash = keyHash, RequestHash = requestHash }, token);
    public Task<CollaborationWriteResult> ActAsync(Guid userId, Guid consortiumId, Guid participantId, ConsortiumParticipantStatus action,
        byte[] expectedRowVersion, byte[] keyHash, byte[] requestHash, CancellationToken token) => WriteAsync("Consortium_ParticipantAction", new { UserPublicId = userId,
            ConsortiumPublicId = consortiumId, ParticipantPublicId = participantId, Action = (byte)action,
            ExpectedRowVersion = expectedRowVersion, KeyHash = keyHash, RequestHash = requestHash }, token);
}
