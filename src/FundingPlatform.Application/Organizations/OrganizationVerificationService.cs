using FundingPlatform.Core.Organizations;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Organizations;

public interface IOrganizationVerificationRepository
{
    Task<OrganizationVerification?> GetAsync(Guid adminUserPublicId,
        Guid organizationPublicId, CancellationToken cancellationToken);

    Task<OrganizationVerification> DecideAsync(Guid adminUserPublicId,
        Guid organizationPublicId, OrganizationVerificationDecision decision,
        CancellationToken cancellationToken);
}

public sealed class OrganizationVerificationDataException(int databaseErrorNumber, Exception inner)
    : Exception("Organization verification operation failed.", inner)
{
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}

public sealed record OrganizationVerificationWriteResult(
    OrganizationVerification? Verification,
    FieldValidationErrors? Errors = null);

public sealed class OrganizationVerificationService(IOrganizationVerificationRepository repository)
{
    public async Task<OrganizationVerification?> GetAsync(Guid adminUserPublicId,
        Guid organizationPublicId, CancellationToken cancellationToken) =>
        (await repository.GetAsync(adminUserPublicId, organizationPublicId, cancellationToken))?
        .WithEffectiveStatus();

    public async Task<OrganizationVerificationWriteResult> DecideAsync(Guid adminUserPublicId,
        Guid organizationPublicId, OrganizationVerificationDecision input,
        CancellationToken cancellationToken)
    {
        var decision = input with { Reason = input.Reason?.Trim() ?? string.Empty };
        var errors = Validate(decision);
        if (errors.Count > 0) return new(null, errors);

        var verification = await repository.DecideAsync(adminUserPublicId,
            organizationPublicId, decision, cancellationToken);
        return new(verification.WithEffectiveStatus());
    }

    private static FieldValidationErrors Validate(OrganizationVerificationDecision decision)
    {
        var errors = new FieldValidationErrors();
        if (decision.Status is < 0 or > 2)
            errors.Set("status", "organization-verification-status", "Selecciona pendiente, verificada o rechazada.");
        if (decision.Reason is null || decision.Reason.Length is < 5 or > 2000)
            errors.Set("reason", "organization-verification-reason", "Indica un motivo de 5 a 2.000 caracteres.", 5, 2000);
        if (decision.ExpectedRevision is < 0 or int.MaxValue)
            errors.Set("expectedRevision", "organization-verification-revision", "Recarga la revisión de la organización.");
        if (decision.ExpectedProfileVersion < 1)
            errors.Set("expectedProfileVersion", "organization-verification-profile-version", "Recarga el perfil de la organización.");
        return errors;
    }
}
