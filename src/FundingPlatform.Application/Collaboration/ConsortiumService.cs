using FundingPlatform.Core.Collaboration;

namespace FundingPlatform.Application.Collaboration;

public sealed class ConsortiumService(IConsortiumRepository repository)
{
    public Task<CollaborationPage<ConsortiumSummary>> ListAsync(Guid userId, int page, int pageSize, CancellationToken token)
    {
        if (!CollaborationRules.ValidPage(page, pageSize)) throw new ArgumentException("Invalid pagination.");
        return repository.ListAsync(userId, page, pageSize, token);
    }
    public Task<ConsortiumDetails?> GetAsync(Guid userId, Guid id, CancellationToken token) => repository.GetAsync(userId, id, token);
    public Task<CollaborationWriteResult> CreateAsync(Guid userId, ConsortiumCreateData input, string key, CancellationToken token)
    {
        var data = input with { Name = (input.Name ?? "").Trim(), Summary = CollaborationRules.Trim(input.Summary) };
        if (data.ProjectId == Guid.Empty || CollaborationRules.ValidateConsortium(data.Name, data.Summary).Count > 0 || !CollaborationRules.ValidKey(key))
            throw new ArgumentException("Invalid consortium.");
        return repository.CreateAsync(userId, data, CollaborationRules.Hash(key), CollaborationRules.Hash(new { operation = "consortium-create", userId, data }), token);
    }
    public Task<CollaborationWriteResult> UpdateAsync(Guid userId, Guid id, ConsortiumUpdateData input, byte[] expected, string key, CancellationToken token)
    {
        Guard(id, expected, key);
        var data = input with { Name = (input.Name ?? "").Trim(), Summary = CollaborationRules.Trim(input.Summary) };
        if (!Enum.IsDefined(data.Status) || CollaborationRules.ValidateConsortium(data.Name, data.Summary).Count > 0) throw new ArgumentException("Invalid consortium.");
        return repository.UpdateAsync(userId, id, data, expected, CollaborationRules.Hash(key), CollaborationRules.Hash(new { operation = "consortium-update", userId, id, data, expected }), token);
    }
    public Task<CollaborationWriteResult> InviteAsync(Guid userId, Guid id, ConsortiumInvitationData input, byte[] expected, string key, CancellationToken token)
    {
        Guard(id, expected, key);
        var data = input with { Contribution = (input.Contribution ?? "").Trim(), Message = (input.Message ?? "").Trim() };
        if (CollaborationRules.ValidateInvitation(data).Count > 0) throw new ArgumentException("Invalid invitation.");
        return repository.InviteAsync(userId, id, data, expected, CollaborationRules.Hash(key), CollaborationRules.Hash(new { operation = "consortium-invite", userId, id, data, expected }), token);
    }
    public Task<CollaborationWriteResult> ActAsync(Guid userId, Guid id, Guid participantId, ConsortiumParticipantStatus action, byte[] expected, string key, CancellationToken token)
    {
        Guard(id, expected, key);
        if (participantId == Guid.Empty || action is < ConsortiumParticipantStatus.Accepted or > ConsortiumParticipantStatus.Removed) throw new ArgumentException("Invalid participation action.");
        return repository.ActAsync(userId, id, participantId, action, expected, CollaborationRules.Hash(key), CollaborationRules.Hash(new { operation = "consortium-participation", userId, id, participantId, action, expected }), token);
    }
    private static void Guard(Guid id, byte[] expected, string key)
    {
        if (id == Guid.Empty || expected.Length != 8 || !CollaborationRules.ValidKey(key)) throw new ArgumentException("Invalid collaboration command.");
    }
}
