using FundingPlatform.Core.Validation;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.Applications;

namespace FundingPlatform.Application.Applications;

public sealed class FundingApplicationService(IFundingApplicationRepository repository)
{
    public const int MinimumIdempotencyKeyLength = 16;
    public const int MaximumIdempotencyKeyLength = 128;
    public const int MaximumNotesLength = 5000;
    public const int MaximumPageNumber = 10_000;
    public const int MaximumPageSize = 50;

    private const decimal MaximumAmount = 999_999_999_999_999.9999m;
    private static readonly JsonSerializerOptions HashOptions = new(JsonSerializerDefaults.Web);

    public async Task<FundingApplicationPageResult> ListAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingApplicationListFilters filters,
        CancellationToken cancellationToken)
    {
        var errors = ValidateList(filters);
        if (errors.Count > 0)
        {
            return new FundingApplicationPageResult(
                FundingApplicationOutcome.ValidationFailed,
                Errors: errors);
        }

        try
        {
            var page = await repository.ListAsync(
                userPublicId,
                organizationPublicId,
                filters,
                cancellationToken);
            return new FundingApplicationPageResult(FundingApplicationOutcome.Success, page);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52101)
        {
            return new FundingApplicationPageResult(FundingApplicationOutcome.NotFound);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52102)
        {
            return new FundingApplicationPageResult(
                FundingApplicationOutcome.ValidationFailed,
                Errors: new FieldValidationErrors
                {
                    { "filters", "api-validation-001", "Los filtros de postulaciones no son válidos." }
                });
        }
    }

    public async Task<FundingApplicationDetailsResult> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        CancellationToken cancellationToken)
    {
        if (fundingApplicationPublicId == Guid.Empty)
        {
            return new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound);
        }

        try
        {
            var application = await repository.GetAsync(
                userPublicId,
                organizationPublicId,
                fundingApplicationPublicId,
                cancellationToken);
            return application is null
                ? new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound)
                : new FundingApplicationDetailsResult(
                    FundingApplicationOutcome.Success,
                    application);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52101)
        {
            return new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound);
        }
    }

    public async Task<FundingApplicationDetailsResult> CreateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid fundingOpportunityPublicId,
        string idempotencyKey,
        FundingApplicationData input,
        CancellationToken cancellationToken)
    {
        var application = Normalize(input with { Status = FundingApplicationStatus.Interested });
        var errors = Validate(application);
        if (projectPublicId == Guid.Empty)
        {
            errors.Set("projectId", "api-validation-002", "Selecciona un proyecto válido.");
        }

        if (fundingOpportunityPublicId == Guid.Empty)
        {
            errors.Set("fundingOpportunityId", "api-validation-003", "Selecciona un fondo válido.");
        }

        var normalizedKey = idempotencyKey?.Trim() ?? string.Empty;
        if (normalizedKey.Length is < MinimumIdempotencyKeyLength or > MaximumIdempotencyKeyLength)
        {
            errors.Set("idempotencyKey", "api-validation-004", $"Idempotency-Key debe tener entre {MinimumIdempotencyKeyLength} y {MaximumIdempotencyKeyLength} caracteres.", min: MinimumIdempotencyKeyLength, max: MaximumIdempotencyKeyLength);
        }

        if (errors.Count > 0)
        {
            return ValidationFailure(errors);
        }

        var idempotencyKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedKey));
        var requestHash = CreateRequestHash(
            organizationPublicId,
            projectPublicId,
            fundingOpportunityPublicId,
            application);

        try
        {
            var mutation = await repository.CreateAsync(
                userPublicId,
                organizationPublicId,
                projectPublicId,
                fundingOpportunityPublicId,
                application,
                idempotencyKeyHash,
                requestHash,
                cancellationToken);
            return await CompleteMutationAsync(
                userPublicId,
                organizationPublicId,
                mutation,
                cancellationToken);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52101)
        {
            return new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52102)
        {
            return InvalidRelations();
        }
    }

    public async Task<FundingApplicationDetailsResult> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        Guid fundingApplicationPublicId,
        byte[] expectedRowVersion,
        FundingApplicationData input,
        CancellationToken cancellationToken)
    {
        var application = Normalize(input);
        var errors = Validate(application);
        if (fundingApplicationPublicId == Guid.Empty)
        {
            errors.Set("applicationId", "api-validation-005", "La postulación no es válida.");
        }

        if (expectedRowVersion is not { Length: 8 })
        {
            errors.Set("ifMatch", "version-invalid", "If-Match no contiene una versión válida.");
        }

        if (errors.Count > 0)
        {
            return ValidationFailure(errors);
        }

        try
        {
            var mutation = await repository.UpdateAsync(
                userPublicId,
                organizationPublicId,
                fundingApplicationPublicId,
                expectedRowVersion,
                application,
                cancellationToken);
            return await CompleteMutationAsync(
                userPublicId,
                organizationPublicId,
                mutation,
                cancellationToken);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52101)
        {
            return new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52102)
        {
            return InvalidRelations();
        }
    }

    public async Task<FundingCalendarResult> ListCalendarAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        DateOnly from,
        DateOnly to,
        CancellationToken cancellationToken)
    {
        var errors = new FieldValidationErrors();
        if (to < from)
        {
            errors.Set("to", "api-validation-007", "La fecha final no puede ser anterior a la inicial.");
        }
        else if (to.DayNumber - from.DayNumber > 365)
        {
            errors.Set("to", "api-validation-008", "El calendario admite un intervalo máximo de 366 días.");
        }

        if (errors.Count > 0)
        {
            return new FundingCalendarResult(
                FundingApplicationOutcome.ValidationFailed,
                from,
                to,
                [],
                errors);
        }

        try
        {
            var items = await repository.ListCalendarAsync(
                userPublicId,
                organizationPublicId,
                from,
                to,
                cancellationToken);
            return new FundingCalendarResult(
                FundingApplicationOutcome.Success,
                from,
                to,
                items);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52101)
        {
            return new FundingCalendarResult(
                FundingApplicationOutcome.NotFound,
                from,
                to,
                []);
        }
        catch (FundingApplicationDataException exception) when (exception.DatabaseErrorNumber == 52102)
        {
            return new FundingCalendarResult(
                FundingApplicationOutcome.ValidationFailed,
                from,
                to,
                [],
                new FieldValidationErrors
                {
                    { "range", "api-validation-009", "El intervalo del calendario no es válido." }
                });
        }
    }

    private async Task<FundingApplicationDetailsResult> CompleteMutationAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        FundingApplicationMutation mutation,
        CancellationToken cancellationToken)
    {
        if (!mutation.Succeeded)
        {
            return mutation.Code switch
            {
                "not-found" => new FundingApplicationDetailsResult(
                    FundingApplicationOutcome.NotFound),
                "idempotency-conflict" => new FundingApplicationDetailsResult(
                    FundingApplicationOutcome.IdempotencyConflict),
                "etag-conflict" => new FundingApplicationDetailsResult(
                    FundingApplicationOutcome.PreconditionFailed),
                "already-exists" => new FundingApplicationDetailsResult(
                    FundingApplicationOutcome.Conflict),
                "invalid-input" => InvalidRelations(),
                _ => new FundingApplicationDetailsResult(FundingApplicationOutcome.Conflict)
            };
        }

        var application = await repository.GetAsync(
            userPublicId,
            organizationPublicId,
            mutation.FundingApplicationPublicId,
            cancellationToken);
        return application is null
            ? new FundingApplicationDetailsResult(FundingApplicationOutcome.NotFound)
            : new FundingApplicationDetailsResult(
                FundingApplicationOutcome.Success,
                application,
                WasReplay: mutation.WasReplay);
    }

    private static FieldValidationErrors ValidateList(FundingApplicationListFilters filters)
    {
        var errors = new FieldValidationErrors();
        if (filters.Status.HasValue && !Enum.IsDefined(filters.Status.Value))
        {
            errors.Set("status", "api-validation-010", "El estado de postulación no es válido.");
        }

        if (filters.ProjectPublicId == Guid.Empty)
        {
            errors.Set("projectId", "api-validation-011", "El filtro de proyecto no es válido.");
        }

        if (filters.FundingOpportunityPublicId == Guid.Empty)
        {
            errors.Set("fundingOpportunityId", "api-validation-012", "El filtro de fondo no es válido.");
        }

        if (filters.PageNumber is < 1 or > MaximumPageNumber)
        {
            errors.Set("page", "api-validation-013", $"La página debe estar entre 1 y {MaximumPageNumber}.", max: MaximumPageNumber);
        }

        if (filters.PageSize is < 1 or > MaximumPageSize)
        {
            errors.Set("pageSize", "api-validation-014", $"El tamaño de página debe estar entre 1 y {MaximumPageSize}.", max: MaximumPageSize);
        }

        return errors;
    }

    private static FundingApplicationData Normalize(FundingApplicationData application) =>
        application with
        {
            Notes = NormalizeOptional(application.Notes),
            Currency = NormalizeOptional(application.Currency)?.ToUpperInvariant()
        };

    private static FieldValidationErrors Validate(FundingApplicationData application)
    {
        var errors = new FieldValidationErrors();
        if (!Enum.IsDefined(application.Status))
        {
            errors.Set("status", "api-validation-010", "El estado de postulación no es válido.");
        }

        if (application.Notes?.Length > MaximumNotesLength)
        {
            errors.Set("notes", "api-validation-015", $"Las notas admiten hasta {MaximumNotesLength} caracteres.", max: MaximumNotesLength);
        }

        if (application.ApplicationDate.HasValue && application.ResultDate.HasValue &&
            application.ResultDate < application.ApplicationDate)
        {
            errors.Set("resultDate", "api-validation-016", "La fecha de resultado no puede ser anterior a la fecha de postulación.");
        }

        if (application.RequestedAmount.HasValue)
        {
            if (application.RequestedAmount <= 0 || application.RequestedAmount > MaximumAmount ||
                decimal.Round(application.RequestedAmount.Value, 4) != application.RequestedAmount)
            {
                errors.Set("requestedAmount", "api-validation-017", "El monto debe ser positivo y admitir como máximo cuatro decimales.");
            }

            if (application.Currency is null)
            {
                errors.Set("currency", "api-validation-018", "Selecciona la moneda del monto solicitado.");
            }
        }
        else if (application.Currency is not null)
        {
            errors.Set("requestedAmount", "api-validation-019", "Indica el monto solicitado antes de seleccionar una moneda.");
        }

        if (application.Currency is not null &&
            (application.Currency.Length != 3 ||
             !application.Currency.All(character => character is >= 'A' and <= 'Z')))
        {
            errors.Set("currency", "currency-invalid", "Selecciona una moneda ISO de tres letras.");
        }

        return errors;
    }

    private static byte[] CreateRequestHash(
        Guid organizationPublicId,
        Guid projectPublicId,
        Guid fundingOpportunityPublicId,
        FundingApplicationData application)
    {
        var canonical = JsonSerializer.Serialize(
            new
            {
                organizationPublicId,
                projectPublicId,
                fundingOpportunityPublicId,
                application.Status,
                application.Notes,
                application.ApplicationDate,
                application.RequestedAmount,
                application.Currency,
                application.ResultDate
            },
            HashOptions);
        return SHA256.HashData(Encoding.UTF8.GetBytes(canonical));
    }

    private static FundingApplicationDetailsResult ValidationFailure(
        IReadOnlyDictionary<string, string[]> errors) =>
        new(FundingApplicationOutcome.ValidationFailed, Errors: errors);

    private static FundingApplicationDetailsResult InvalidRelations() =>
        ValidationFailure(new FieldValidationErrors
        {
            { "application", "api-validation-021", "La postulación contiene relaciones o datos inválidos." }
        });

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
