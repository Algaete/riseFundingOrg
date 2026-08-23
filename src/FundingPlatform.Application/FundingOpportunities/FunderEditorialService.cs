using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FunderEditorialService(IFunderRepository repository)
{
    public async Task<FundingEditorialQueryResult<FunderPage>> ListAdminAsync(
        Guid adminUserPublicId,
        string? query,
        FundingPublicationStatus? publicationStatus,
        bool includeInactive,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        ValidatePagination(pageNumber, pageSize);
        var normalizedQuery = NormalizeQuery(query);
        try
        {
            var page = await repository.ListAdminAsync(
                adminUserPublicId, normalizedQuery, publicationStatus, includeInactive,
                pageNumber, pageSize, cancellationToken);
            return new FundingEditorialQueryResult<FunderPage>(FundingEditorialOutcome.Success, page);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialQueryResult<FunderPage>(FundingEditorialOutcome.Forbidden);
        }
    }

    public async Task<FundingEditorialQueryResult<FunderDetails>> GetAdminAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            var funder = await repository.GetAdminAsync(
                adminUserPublicId, funderPublicId, cancellationToken);
            return funder is null
                ? new FundingEditorialQueryResult<FunderDetails>(FundingEditorialOutcome.NotFound)
                : new FundingEditorialQueryResult<FunderDetails>(FundingEditorialOutcome.Success, funder);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialQueryResult<FunderDetails>(FundingEditorialOutcome.Forbidden);
        }
    }

    public Task<FundingEditorialCommandResult> CreateAsync(
        Guid adminUserPublicId,
        FunderData input,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        WriteAsync(adminUserPublicId, null, null, input, idempotencyKey, cancellationToken);

    public Task<FundingEditorialCommandResult> UpdateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        FunderData input,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        WriteAsync(adminUserPublicId, funderPublicId, expectedRowVersion, input,
            idempotencyKey, cancellationToken);

    public Task<FundingEditorialCommandResult> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            FundingEditorialAction.SubmitReview,
            adminUserPublicId,
            funderPublicId,
            expectedRowVersion,
            idempotencyKey,
            payload: null,
            static (targetRepository, userId, entityId, rowVersion, _, keyHash, requestHash, token) =>
                targetRepository.RequestPublicationAsync(
                    userId, entityId, rowVersion, keyHash, requestHash, token),
            cancellationToken);

    public Task<FundingEditorialCommandResult> ReviewAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        FundingReviewDecision decision,
        string? reason,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = FundingEditorialServiceSupport.NormalizeOptional(reason);
        var reviewErrors = FundingEditorialServiceSupport.ValidateReview(decision, normalizedReason);
        if (reviewErrors.Count > 0)
        {
            return Task.FromResult(new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, funderPublicId,
                Errors: reviewErrors, Code: "invalid-review"));
        }

        return ExecuteWorkflowAsync(
            decision == FundingReviewDecision.Approve
                ? FundingEditorialAction.Approve
                : FundingEditorialAction.Reject,
            adminUserPublicId,
            funderPublicId,
            expectedRowVersion,
            idempotencyKey,
            normalizedReason,
            (targetRepository, userId, entityId, rowVersion, payload, keyHash, requestHash, token) =>
                targetRepository.ReviewAsync(
                    userId, entityId, decision, payload, rowVersion, keyHash, requestHash, token),
            cancellationToken);
    }

    public Task<FundingEditorialCommandResult> DeactivateAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string? reason,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = FundingEditorialServiceSupport.NormalizeOptional(reason);
        if (normalizedReason?.Length > FundingEditorialServiceSupport.MaximumReasonLength)
        {
            return Task.FromResult(new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, funderPublicId,
                Errors: new Dictionary<string, string[]>
                {
                    ["reason"] =
                        [$"Admite hasta {FundingEditorialServiceSupport.MaximumReasonLength} caracteres."]
                },
                Code: "invalid-deactivation"));
        }

        return ExecuteWorkflowAsync(
            FundingEditorialAction.Deactivate,
            adminUserPublicId,
            funderPublicId,
            expectedRowVersion,
            idempotencyKey,
            normalizedReason,
            static (targetRepository, userId, entityId, rowVersion, payload, keyHash, requestHash, token) =>
                targetRepository.DeactivateAsync(
                    userId, entityId, payload, rowVersion, keyHash, requestHash, token),
            cancellationToken);
    }

    public Task<FundingEditorialCommandResult> StartCorrectionAsync(
        Guid adminUserPublicId,
        Guid funderPublicId,
        string? reason,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = FundingEditorialServiceSupport.NormalizeOptional(reason);
        var validationErrors = FundingEditorialServiceSupport.ValidateCorrectionReason(
            normalizedReason);
        if (validationErrors.Count > 0)
        {
            return Task.FromResult(new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, funderPublicId,
                Errors: validationErrors, Code: "invalid-correction"));
        }

        return ExecuteWorkflowAsync(
            FundingEditorialAction.StartCorrection,
            adminUserPublicId,
            funderPublicId,
            expectedRowVersion,
            idempotencyKey,
            normalizedReason,
            static (targetRepository, userId, entityId, rowVersion, payload, keyHash, requestHash, token) =>
                targetRepository.StartCorrectionAsync(
                    userId, entityId, payload!, rowVersion, keyHash, requestHash, token),
            cancellationToken);
    }

    public Task<PublicFunderPage> ListPublishedAsync(
        string? query,
        int pageNumber,
        int pageSize,
        CancellationToken cancellationToken)
    {
        ValidatePagination(pageNumber, Math.Min(pageSize, 50));
        if (pageSize > 50)
        {
            throw new ArgumentOutOfRangeException(nameof(pageSize));
        }

        return repository.ListPublishedAsync(
            NormalizeQuery(query), pageNumber, pageSize, cancellationToken);
    }

    public Task<PublicFunderDetails?> GetPublishedBySlugAsync(
        string slug,
        CancellationToken cancellationToken)
    {
        var normalized = slug?.Trim();
        return string.IsNullOrWhiteSpace(normalized) || normalized.Length > 180
            ? Task.FromResult<PublicFunderDetails?>(null)
            : repository.GetPublishedBySlugAsync(normalized, cancellationToken);
    }

    private async Task<FundingEditorialCommandResult> WriteAsync(
        Guid adminUserPublicId,
        Guid? funderPublicId,
        byte[]? expectedRowVersion,
        FunderData input,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(input);
        var data = Normalize(input);
        var validationErrors = Validate(data);
        if (!FundingEditorialServiceSupport.TryPrepareCommand(
                funderPublicId.HasValue ? "UpdateFunder" : "CreateFunder",
                funderPublicId,
                expectedRowVersion,
                funderPublicId.HasValue,
                idempotencyKey,
                data,
                out var keyHash,
                out var requestHash,
                out _,
                out var commandErrors))
        {
            Merge(validationErrors, commandErrors);
        }

        if (validationErrors.Count > 0)
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed,
                funderPublicId ?? Guid.Empty,
                Errors: validationErrors,
                Code: "funder-validation");
        }

        try
        {
            var mutation = funderPublicId.HasValue
                ? await repository.UpdateAsync(
                    adminUserPublicId, funderPublicId.Value, expectedRowVersion!, data,
                    keyHash, requestHash, cancellationToken)
                : await repository.CreateAsync(
                    adminUserPublicId,
                    FundingEditorialServiceSupport.CreateSlug(data.Name, keyHash, 180),
                    data, keyHash, requestHash, cancellationToken);
            return FundingEditorialServiceSupport.MapMutation(mutation);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.Forbidden, funderPublicId ?? Guid.Empty,
                Code: "forbidden");
        }
    }

    private async Task<FundingEditorialCommandResult> ExecuteWorkflowAsync(
        FundingEditorialAction action,
        Guid adminUserPublicId,
        Guid funderPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        string? payload,
        Func<IFunderRepository, Guid, Guid, byte[], string?, byte[], byte[], CancellationToken,
            Task<FundingEditorialMutation>> execute,
        CancellationToken cancellationToken)
    {
        if (!FundingEditorialServiceSupport.TryPrepareCommand(
                $"Funder{action}", funderPublicId, expectedRowVersion,
                requiresRowVersion: true, idempotencyKey, payload ?? string.Empty,
                out var keyHash, out var requestHash, out _, out var errors))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, funderPublicId,
                Errors: errors, Code: "funder-workflow-validation");
        }

        try
        {
            return FundingEditorialServiceSupport.MapMutation(await execute(
                repository, adminUserPublicId, funderPublicId, expectedRowVersion,
                payload, keyHash, requestHash, cancellationToken));
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.Forbidden, funderPublicId, Code: "forbidden");
        }
    }

    private static FunderData Normalize(FunderData input)
    {
        var name = input.Name?.Trim() ?? string.Empty;
        var aliases = (input.Aliases ?? [])
            .Select(alias => alias?.Trim())
            .Where(alias => !string.IsNullOrWhiteSpace(alias))
            .Select(alias => alias!)
            .Where(alias => !string.Equals(alias, name, StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return input with
        {
            Name = name,
            Description = FundingEditorialServiceSupport.NormalizeOptional(input.Description),
            WebsiteUrl = FundingEditorialServiceSupport.NormalizeOptional(input.WebsiteUrl),
            Aliases = aliases
        };
    }

    private static Dictionary<string, string[]> Validate(FunderData data)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (data.Name.Length is < 2 or > 300)
        {
            errors["name"] = ["El nombre debe tener entre 2 y 300 caracteres."];
        }

        FundingEditorialServiceSupport.ValidateLength(data.Description, 2000, "description", errors);
        if (!FundingEditorialServiceSupport.IsSafeHttpUrl(data.WebsiteUrl))
        {
            errors["websiteUrl"] = ["Usa una URL HTTP o HTTPS válida, sin credenciales."];
        }

        if (data.CountryId is <= 0)
        {
            errors["countryId"] = ["El país no es válido."];
        }

        if (data.Aliases.Count > 50 || data.Aliases.Any(alias => alias.Length is < 2 or > 300))
        {
            errors["aliases"] = ["Admite hasta 50 aliases de 2 a 300 caracteres."];
        }

        return errors;
    }

    private static string? NormalizeQuery(string? query)
    {
        var normalized = FundingEditorialServiceSupport.NormalizeOptional(query);
        if (normalized?.Length > 300)
        {
            throw new ArgumentOutOfRangeException(nameof(query));
        }

        return normalized;
    }

    private static void ValidatePagination(int pageNumber, int pageSize)
    {
        if (pageNumber < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(pageNumber));
        }

        if (pageSize is < 1 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(pageSize));
        }
    }

    private static void Merge(
        IDictionary<string, string[]> target,
        IReadOnlyDictionary<string, string[]> source)
    {
        foreach (var (key, value) in source)
        {
            target[key] = value;
        }
    }
}
