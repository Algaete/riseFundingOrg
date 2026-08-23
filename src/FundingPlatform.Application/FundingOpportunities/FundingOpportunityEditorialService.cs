using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.Application.FundingOpportunities;

public sealed class FundingOpportunityEditorialService(
    IFundingOpportunityEditorialRepository repository,
    TimeProvider timeProvider)
{
    public async Task<FundingEditorialQueryResult<FundingOpportunityAdminPage>> ListAdminAsync(
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
            return new FundingEditorialQueryResult<FundingOpportunityAdminPage>(
                FundingEditorialOutcome.Success, page);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialQueryResult<FundingOpportunityAdminPage>(
                FundingEditorialOutcome.Forbidden);
        }
    }

    public async Task<FundingEditorialQueryResult<FundingOpportunityAdminDetails>> GetAdminAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        CancellationToken cancellationToken)
    {
        try
        {
            var opportunity = await repository.GetAdminAsync(
                adminUserPublicId, opportunityPublicId, cancellationToken);
            return opportunity is null
                ? new FundingEditorialQueryResult<FundingOpportunityAdminDetails>(
                    FundingEditorialOutcome.NotFound)
                : new FundingEditorialQueryResult<FundingOpportunityAdminDetails>(
                    FundingEditorialOutcome.Success, opportunity);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialQueryResult<FundingOpportunityAdminDetails>(
                FundingEditorialOutcome.Forbidden);
        }
    }

    public Task<FundingEditorialCommandResult> CreateAsync(
        Guid adminUserPublicId,
        FundingOpportunityEditorialData input,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        WriteAsync(adminUserPublicId, null, null, input, idempotencyKey, cancellationToken);

    public Task<FundingEditorialCommandResult> UpdateAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        FundingOpportunityEditorialData input,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        WriteAsync(adminUserPublicId, opportunityPublicId, expectedRowVersion, input,
            idempotencyKey, cancellationToken);

    public Task<FundingEditorialCommandResult> RequestPublicationAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken) =>
        ExecuteWorkflowAsync(
            FundingEditorialAction.SubmitReview,
            adminUserPublicId,
            opportunityPublicId,
            expectedRowVersion,
            idempotencyKey,
            payload: null,
            static (targetRepository, userId, entityId, rowVersion, _, keyHash, requestHash, token) =>
                targetRepository.RequestPublicationAsync(
                    userId, entityId, rowVersion, keyHash, requestHash, token),
            cancellationToken);

    public Task<FundingEditorialCommandResult> ReviewAsync(
        Guid adminUserPublicId,
        Guid opportunityPublicId,
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
                FundingEditorialOutcome.ValidationFailed, opportunityPublicId,
                Errors: reviewErrors, Code: "invalid-review"));
        }

        return ExecuteWorkflowAsync(
            decision == FundingReviewDecision.Approve
                ? FundingEditorialAction.Approve
                : FundingEditorialAction.Reject,
            adminUserPublicId,
            opportunityPublicId,
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
        Guid opportunityPublicId,
        string? reason,
        byte[] expectedRowVersion,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        var normalizedReason = FundingEditorialServiceSupport.NormalizeOptional(reason);
        if (normalizedReason?.Length > FundingEditorialServiceSupport.MaximumReasonLength)
        {
            return Task.FromResult(new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, opportunityPublicId,
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
            opportunityPublicId,
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
        Guid opportunityPublicId,
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
                FundingEditorialOutcome.ValidationFailed, opportunityPublicId,
                Errors: validationErrors, Code: "invalid-correction"));
        }

        return ExecuteWorkflowAsync(
            FundingEditorialAction.StartCorrection,
            adminUserPublicId,
            opportunityPublicId,
            expectedRowVersion,
            idempotencyKey,
            normalizedReason,
            static (targetRepository, userId, entityId, rowVersion, payload, keyHash, requestHash, token) =>
                targetRepository.StartCorrectionAsync(
                    userId, entityId, payload!, rowVersion, keyHash, requestHash, token),
            cancellationToken);
    }

    private async Task<FundingEditorialCommandResult> WriteAsync(
        Guid adminUserPublicId,
        Guid? opportunityPublicId,
        byte[]? expectedRowVersion,
        FundingOpportunityEditorialData input,
        string idempotencyKey,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(input);
        var data = Normalize(input);
        var validationErrors = Validate(data);
        if (!FundingEditorialServiceSupport.TryPrepareCommand(
                opportunityPublicId.HasValue ? "UpdateFundingOpportunity" : "CreateFundingOpportunity",
                opportunityPublicId,
                expectedRowVersion,
                opportunityPublicId.HasValue,
                idempotencyKey,
                data,
                out var keyHash,
                out var requestHash,
                out var snapshotJson,
                out var commandErrors))
        {
            Merge(validationErrors, commandErrors);
        }

        if (validationErrors.Count > 0)
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed,
                opportunityPublicId ?? Guid.Empty,
                Errors: validationErrors,
                Code: "funding-opportunity-validation");
        }

        var contentHash = SHA256.HashData(Encoding.UTF8.GetBytes(snapshotJson));
        var dataQualityScore = CalculateDataQualityScore(data);
        try
        {
            var mutation = opportunityPublicId.HasValue
                ? await repository.UpdateAsync(
                    adminUserPublicId, opportunityPublicId.Value, expectedRowVersion!, data,
                    snapshotJson, contentHash, dataQualityScore, keyHash, requestHash,
                    cancellationToken)
                : await repository.CreateAsync(
                    adminUserPublicId,
                    FundingEditorialServiceSupport.CreateSlug(data.Title, keyHash, 320),
                    data, snapshotJson, contentHash, dataQualityScore, keyHash, requestHash,
                    cancellationToken);
            return FundingEditorialServiceSupport.MapMutation(mutation);
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.Forbidden, opportunityPublicId ?? Guid.Empty,
                Code: "forbidden");
        }
    }

    private async Task<FundingEditorialCommandResult> ExecuteWorkflowAsync(
        FundingEditorialAction action,
        Guid adminUserPublicId,
        Guid opportunityPublicId,
        byte[] expectedRowVersion,
        string idempotencyKey,
        string? payload,
        Func<IFundingOpportunityEditorialRepository, Guid, Guid, byte[], string?, byte[], byte[],
            CancellationToken, Task<FundingEditorialMutation>> execute,
        CancellationToken cancellationToken)
    {
        if (!FundingEditorialServiceSupport.TryPrepareCommand(
                $"FundingOpportunity{action}", opportunityPublicId, expectedRowVersion,
                requiresRowVersion: true, idempotencyKey, payload ?? string.Empty,
                out var keyHash, out var requestHash, out _, out var errors))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.ValidationFailed, opportunityPublicId,
                Errors: errors, Code: "funding-opportunity-workflow-validation");
        }

        try
        {
            return FundingEditorialServiceSupport.MapMutation(await execute(
                repository, adminUserPublicId, opportunityPublicId, expectedRowVersion,
                payload, keyHash, requestHash, cancellationToken));
        }
        catch (FundingEditorialDataException exception)
            when (FundingEditorialServiceSupport.IsForbidden(exception))
        {
            return new FundingEditorialCommandResult(
                FundingEditorialOutcome.Forbidden, opportunityPublicId, Code: "forbidden");
        }
    }

    private static FundingOpportunityEditorialData Normalize(
        FundingOpportunityEditorialData input)
    {
        var funders = (input.Funders ?? [])
            .OrderBy(link => link.FunderPublicId)
            .ThenBy(link => link.Role)
            .ToArray();
        return input with
        {
            Title = input.Title?.Trim() ?? string.Empty,
            Summary = FundingEditorialServiceSupport.NormalizeOptional(input.Summary),
            Description = FundingEditorialServiceSupport.NormalizeOptional(input.Description),
            SponsorName = input.SponsorName?.Trim() ?? string.Empty,
            SponsorUrl = FundingEditorialServiceSupport.NormalizeOptional(input.SponsorUrl),
            ApplicationUrl = FundingEditorialServiceSupport.NormalizeOptional(input.ApplicationUrl),
            Funders = funders,
            ExternalId = FundingEditorialServiceSupport.NormalizeOptional(input.ExternalId),
            SourceUrl = input.SourceUrl?.Trim() ?? string.Empty,
            Currency = FundingEditorialServiceSupport.NormalizeOptional(input.Currency)?.ToUpperInvariant(),
            CloseAtUtc = input.CloseAtUtc?.ToUniversalTime(),
            DeadlineTimeZoneId = FundingEditorialServiceSupport.NormalizeOptional(
                input.DeadlineTimeZoneId),
            EligibilityDescription = FundingEditorialServiceSupport.NormalizeOptional(input.EligibilityDescription),
            Requirements = FundingEditorialServiceSupport.NormalizeOptional(input.Requirements),
            Objectives = FundingEditorialServiceSupport.NormalizeOptional(input.Objectives),
            AllowedActivities = FundingEditorialServiceSupport.NormalizeOptional(input.AllowedActivities),
            ExcludedActivities = FundingEditorialServiceSupport.NormalizeOptional(input.ExcludedActivities),
            Restrictions = FundingEditorialServiceSupport.NormalizeOptional(input.Restrictions),
            TargetOrganizationsDescription = FundingEditorialServiceSupport.NormalizeOptional(
                input.TargetOrganizationsDescription),
            TargetPopulationsDescription = FundingEditorialServiceSupport.NormalizeOptional(
                input.TargetPopulationsDescription),
            LastVerifiedAtUtc = input.LastVerifiedAtUtc?.ToUniversalTime(),
            CountryIds = (input.CountryIds ?? []).Distinct().Order().ToArray(),
            RegionIds = (input.RegionIds ?? []).Distinct().Order().ToArray(),
            CategoryIds = (input.CategoryIds ?? []).Distinct().Order().ToArray(),
            BeneficiaryTypeIds = (input.BeneficiaryTypeIds ?? []).Distinct().Order().ToArray(),
            ProjectTypeIds = (input.ProjectTypeIds ?? []).Distinct().Order().ToArray()
        };
    }

    private Dictionary<string, string[]> Validate(FundingOpportunityEditorialData data)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (data.Title.Length is < 3 or > 350)
        {
            errors["title"] = ["El título debe tener entre 3 y 350 caracteres."];
        }

        if (data.SponsorName.Length is < 2 or > 300)
        {
            errors["sponsorName"] = ["El organismo debe tener entre 2 y 300 caracteres."];
        }

        FundingEditorialServiceSupport.ValidateLength(data.Summary, 2000, "summary", errors);
        FundingEditorialServiceSupport.ValidateLength(data.Description, 50_000, "description", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.EligibilityDescription, 30_000, "eligibilityDescription", errors);
        FundingEditorialServiceSupport.ValidateLength(data.Requirements, 30_000, "requirements", errors);
        FundingEditorialServiceSupport.ValidateLength(data.Objectives, 30_000, "objectives", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.AllowedActivities, 30_000, "allowedActivities", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.ExcludedActivities, 30_000, "excludedActivities", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.Restrictions, 30_000, "restrictions", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.TargetOrganizationsDescription, 2000,
            "targetOrganizationsDescription", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.TargetPopulationsDescription, 2000,
            "targetPopulationsDescription", errors);
        FundingEditorialServiceSupport.ValidateLength(
            data.DeadlineTimeZoneId, 100, "deadlineTimeZoneId", errors);

        ValidateUrl(data.SponsorUrl, "sponsorUrl", required: false, errors);
        ValidateUrl(data.ApplicationUrl, "applicationUrl", required: false, errors);
        ValidateUrl(data.SourceUrl, "sourceUrl", required: true, errors);
        if (data.FundingSourceId <= 0)
        {
            errors["fundingSourceId"] = ["Selecciona una fuente editorial activa."];
        }

        if (data.IssuerCountryId is <= 0)
        {
            errors["issuerCountryId"] = ["El país emisor no es válido."];
        }

        if (data.FundingTypeId is <= 0)
        {
            errors["fundingTypeId"] = ["El tipo de financiamiento no es válido."];
        }

        if (data.ExternalId?.Length > 250)
        {
            errors["externalId"] = ["Admite hasta 250 caracteres."];
        }

        if (data.Funders.Count == 0 ||
            data.Funders.Count(link => link.Role == FunderOpportunityRole.Primary) != 1)
        {
            errors["funders"] = ["Selecciona exactamente un funder primario."];
        }
        else if (data.Funders.Any(link => link.FunderPublicId == Guid.Empty ||
                     link.Role is < FunderOpportunityRole.Primary or > FunderOpportunityRole.Administrator) ||
                 data.Funders.GroupBy(link => link.FunderPublicId).Any(group => group.Count() > 1))
        {
            errors["funders"] = ["Cada funder debe ser válido, único y tener un rol permitido."];
        }

        if (data.Currency is not null &&
            (data.Currency.Length != 3 || data.Currency.Any(character => character is < 'A' or > 'Z')))
        {
            errors["currency"] = ["La moneda debe usar un código ISO de tres letras."];
        }

        if (data.AmountStatus is < FundingAmountStatus.Unknown or > FundingAmountStatus.NotDisclosed)
        {
            errors["amountStatus"] = ["amountStatus debe estar entre 0 y 2."];
        }
        else if (data.AmountStatus == FundingAmountStatus.Specified &&
                 (!data.MinimumAmount.HasValue && !data.MaximumAmount.HasValue ||
                  data.Currency is null))
        {
            errors["amountStatus"] =
                ["Los montos especificados requieren moneda y al menos un monto."];
        }
        else if (data.AmountStatus != FundingAmountStatus.Specified &&
                 (data.MinimumAmount.HasValue || data.MaximumAmount.HasValue || data.Currency is not null))
        {
            errors["amountStatus"] =
                ["Los estados unknown/not-disclosed no admiten moneda ni montos."];
        }

        if (data.MinimumAmount is < 0 || data.MaximumAmount is < 0 ||
            data.MaximumAmount < data.MinimumAmount)
        {
            errors["maximumAmount"] = ["Los montos deben ser positivos y el máximo no puede ser menor al mínimo."];
        }

        if (data.OpenDate.HasValue && data.CloseDate.HasValue && data.CloseDate < data.OpenDate)
        {
            errors["closeDate"] = ["El cierre no puede ser anterior a la apertura."];
        }

        ValidateDeadline(data, errors);

        if (data.MinimumOperatingYears is < 0)
        {
            errors["minimumOperatingYears"] = ["No puede ser negativo."];
        }

        if (data.CofundingPercentage is < 0 or > 100 ||
            data.RequiresCofunding is null && data.CofundingPercentage.HasValue ||
            data.RequiresCofunding == false && data.CofundingPercentage is not null and not 0 ||
            data.RequiresCofunding == true && data.CofundingPercentage is null or <= 0)
        {
            errors["cofundingPercentage"] =
                ["Debe ser mayor que 0 y hasta 100 cuando el cofinanciamiento es requerido."];
        }

        if (data.GeographicScope is < FundingGeographicScope.Unknown or > FundingGeographicScope.Global)
        {
            errors["geographicScope"] = ["geographicScope debe estar entre 0 y 2."];
        }
        else if (data.GeographicScope == FundingGeographicScope.Specified &&
                 data.CountryIds.Count == 0)
        {
            errors["countryIds"] =
                ["El alcance geográfico especificado requiere al menos un país."];
        }

        if (data.RemoteApplication is < FundingRemoteApplication.Unknown or > FundingRemoteApplication.Yes)
        {
            errors["remoteApplication"] = ["remoteApplication debe estar entre 0 y 2."];
        }

        if (data.LastVerifiedAtUtc > timeProvider.GetUtcNow().AddMinutes(5))
        {
            errors["lastVerifiedAtUtc"] = ["No puede estar en el futuro."];
        }

        ValidatePositiveIds(data.CountryIds, "countryIds", errors);
        ValidatePositiveIds(data.RegionIds, "regionIds", errors);
        ValidatePositiveIds(data.CategoryIds, "categoryIds", errors);
        ValidatePositiveIds(data.BeneficiaryTypeIds, "beneficiaryTypeIds", errors);
        ValidatePositiveIds(data.ProjectTypeIds, "projectTypeIds", errors);
        return errors;
    }

    private static void ValidateDeadline(
        FundingOpportunityEditorialData data,
        IDictionary<string, string[]> errors)
    {
        if (data.DeadlineType is < FundingDeadlineType.Unknown or > FundingDeadlineType.Rolling)
        {
            errors["deadlineType"] = ["deadlineType debe estar entre 0 y 2."];
            return;
        }

        if (data.DeadlinePrecision is < FundingDeadlinePrecision.Unknown or
            > FundingDeadlinePrecision.DateTime)
        {
            errors["deadlinePrecision"] = ["deadlinePrecision debe estar entre 0 y 2."];
            return;
        }

        var valid = data.DeadlineType switch
        {
            FundingDeadlineType.Unknown =>
                data.DeadlinePrecision == FundingDeadlinePrecision.Unknown &&
                !data.CloseDate.HasValue && !data.CloseAtUtc.HasValue,
            FundingDeadlineType.Rolling =>
                data.DeadlinePrecision == FundingDeadlinePrecision.Unknown &&
                !data.CloseDate.HasValue && !data.CloseAtUtc.HasValue,
            FundingDeadlineType.Fixed when data.DeadlinePrecision == FundingDeadlinePrecision.Date =>
                data.CloseDate.HasValue && !data.CloseAtUtc.HasValue,
            FundingDeadlineType.Fixed when data.DeadlinePrecision == FundingDeadlinePrecision.DateTime =>
                data.CloseDate.HasValue && data.CloseAtUtc.HasValue &&
                !string.IsNullOrWhiteSpace(data.DeadlineTimeZoneId),
            _ => false
        };
        if (!valid)
        {
            errors["deadline"] =
                ["La combinación de tipo, precisión, fecha, hora y zona horaria no es válida."];
            return;
        }

        if (data.DeadlinePrecision != FundingDeadlinePrecision.DateTime)
        {
            return;
        }

        try
        {
            var timeZone = TimeZoneInfo.FindSystemTimeZoneById(data.DeadlineTimeZoneId!);
            var localDeadline = TimeZoneInfo.ConvertTime(data.CloseAtUtc!.Value, timeZone);
            if (DateOnly.FromDateTime(localDeadline.DateTime) != data.CloseDate)
            {
                errors["closeAtUtc"] =
                    ["closeAtUtc no corresponde a closeDate en deadlineTimeZoneId."];
            }
        }
        catch (TimeZoneNotFoundException)
        {
            errors["deadlineTimeZoneId"] = ["La zona horaria no existe."];
        }
        catch (InvalidTimeZoneException)
        {
            errors["deadlineTimeZoneId"] = ["La zona horaria no es válida."];
        }
    }

    private static decimal CalculateDataQualityScore(FundingOpportunityEditorialData data)
    {
        var score = 40m;
        score += data.Description is null ? 0 : 10;
        score += data.EligibilityDescription is null ? 0 : 10;
        score += data.DeadlineType == FundingDeadlineType.Unknown ? 0 : 10;
        score += data.AmountStatus == FundingAmountStatus.Specified ? 10 : 0;
        score += data.CountryIds.Count == 0 ? 0 : 5;
        score += data.CategoryIds.Count == 0 ? 0 : 5;
        score += data.Funders.Count == 0 ? 0 : 5;
        score += string.IsNullOrWhiteSpace(data.SourceUrl) ? 0 : 5;
        return Math.Min(score, 100m);
    }

    private static void ValidateUrl(
        string? value,
        string field,
        bool required,
        IDictionary<string, string[]> errors)
    {
        if (required && string.IsNullOrWhiteSpace(value))
        {
            errors[field] = ["La URL de fuente oficial es obligatoria."];
        }
        else if (!FundingEditorialServiceSupport.IsSafeHttpUrl(value))
        {
            errors[field] = ["Usa una URL HTTP o HTTPS válida, sin credenciales."];
        }
    }

    private static void ValidatePositiveIds<T>(
        IReadOnlyList<T> values,
        string field,
        IDictionary<string, string[]> errors)
        where T : struct, IComparable<T>
    {
        if (values.Any(value => value.CompareTo(default) <= 0))
        {
            errors[field] = ["Contiene identificadores no válidos."];
        }
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
