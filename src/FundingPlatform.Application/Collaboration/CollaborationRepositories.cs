using FundingPlatform.Core.Collaboration;

namespace FundingPlatform.Application.Collaboration;

public interface IProfessionalProfileRepository
{
    Task<ProfessionalProfile?> GetOwnAsync(Guid userId, CancellationToken cancellationToken);
    Task<CollaborationPage<ProfessionalDirectoryEntry>> SearchAsync(Guid userId, ProfessionalDirectoryFilters filters, CancellationToken cancellationToken);
    Task<CollaborationWriteResult> SaveAsync(Guid userId, ProfessionalProfileData data, byte[]? expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken cancellationToken);
}

public interface IConsortiumRepository
{
    Task<CollaborationPage<ConsortiumSummary>> ListAsync(Guid userId, int page, int pageSize, CancellationToken cancellationToken);
    Task<ConsortiumDetails?> GetAsync(Guid userId, Guid consortiumId, CancellationToken cancellationToken);
    Task<CollaborationWriteResult> CreateAsync(Guid userId, ConsortiumCreateData data, byte[] keyHash, byte[] requestHash, CancellationToken cancellationToken);
    Task<CollaborationWriteResult> UpdateAsync(Guid userId, Guid consortiumId, ConsortiumUpdateData data, byte[] expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken cancellationToken);
    Task<CollaborationWriteResult> InviteAsync(Guid userId, Guid consortiumId, ConsortiumInvitationData data, byte[] expectedRowVersion,
        byte[] keyHash, byte[] requestHash, CancellationToken cancellationToken);
    Task<CollaborationWriteResult> ActAsync(Guid userId, Guid consortiumId, Guid participantId, ConsortiumParticipantStatus action,
        byte[] expectedRowVersion, byte[] keyHash, byte[] requestHash, CancellationToken cancellationToken);
}

public sealed class CollaborationDataException(int databaseErrorNumber, Exception innerException)
    : Exception("Collaboration persistence operation failed.", innerException)
{
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
