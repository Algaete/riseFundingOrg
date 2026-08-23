using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.Organizations;

namespace FundingPlatform.Application.Organizations;

public sealed class OrganizationProfileService(IOrganizationRepository repository)
{
    private static readonly JsonSerializerOptions SnapshotOptions = new(JsonSerializerDefaults.Web);

    public Task<OrganizationCatalogs> GetCatalogsAsync(CancellationToken cancellationToken) =>
        repository.GetCatalogsAsync(cancellationToken);

    public Task<IReadOnlyList<OrganizationSummary>> ListAsync(
        Guid userPublicId,
        CancellationToken cancellationToken) =>
        repository.ListForUserAsync(userPublicId, cancellationToken);

    public async Task<OrganizationWriteResult> CreateAsync(
        Guid userPublicId,
        string name,
        short homeCountryId,
        short organizationTypeId,
        CancellationToken cancellationToken)
    {
        var profile = new OrganizationProfileData(
            Normalize(name), null, null, homeCountryId, organizationTypeId,
            null, null, null, null, null, 0, null,
            null, null, null, null, null, null,
            [], [], [], [], [], [], []);
        var errors = Validate(profile, requireCollections: false);
        if (errors.Count > 0)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors: errors);
        }

        var snapshot = CreateSnapshot(profile);
        try
        {
            var created = await repository.CreateAsync(
                userPublicId,
                profile,
                snapshot.Json,
                snapshot.Hash,
                cancellationToken);
            return new OrganizationWriteResult(OrganizationWriteOutcome.Success, created);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51202)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.OwnedLimitReached);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber is 547 or 51201)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors:
                new Dictionary<string, string[]> { ["organization"] = ["Los datos de organización no son válidos."] });
        }
    }

    public Task<OrganizationProfile?> GetAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        CancellationToken cancellationToken) =>
        repository.GetProfileAsync(userPublicId, organizationPublicId, cancellationToken);

    public async Task<OrganizationWriteResult> UpdateAsync(
        Guid userPublicId,
        Guid organizationPublicId,
        byte[] expectedRowVersion,
        OrganizationProfileData input,
        CancellationToken cancellationToken)
    {
        var profile = Normalize(input);
        var errors = Validate(profile, requireCollections: true);
        if (expectedRowVersion.Length != 8)
        {
            errors["ifMatch"] = ["If-Match no contiene una versión válida."];
        }

        if (errors.Count > 0)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors: errors);
        }

        var completeness = CalculateCompleteness(profile);
        var status = completeness >= 80 ? (byte)2 : completeness > 0 ? (byte)1 : (byte)0;
        var snapshot = CreateSnapshot(profile);

        try
        {
            var updated = await repository.UpdateProfileAsync(
                userPublicId,
                organizationPublicId,
                expectedRowVersion,
                profile,
                status,
                completeness,
                snapshot.Json,
                snapshot.Hash,
                cancellationToken);
            return new OrganizationWriteResult(OrganizationWriteOutcome.Success, updated);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51009)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.Conflict);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber is 51006 or 51204)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.NotFound);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber is 51004 or 51007 or 51010 or 547)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors:
                new Dictionary<string, string[]> { ["profile"] = ["El perfil contiene catálogos o relaciones inválidas."] });
        }
    }

    public static decimal CalculateCompleteness(OrganizationProfileData profile)
    {
        var completed = 0;
        completed += !string.IsNullOrWhiteSpace(profile.Name) ? 1 : 0;
        completed += profile.HomeCountryId > 0 && profile.OrganizationTypeId > 0 ? 1 : 0;
        completed += profile.LegalEntityTypeId.HasValue && profile.EstablishedYear.HasValue ? 1 : 0;
        completed += !string.IsNullOrWhiteSpace(profile.Description) ? 1 : 0;
        completed += profile.CountryIds.Count > 0 ? 1 : 0;
        completed += profile.CategoryIds.Count > 0 ? 1 : 0;
        completed += profile.BeneficiaryTypeIds.Count > 0 ? 1 : 0;
        completed += profile.ProjectTypeIds.Count > 0 ? 1 : 0;
        completed += profile.DesiredFundingMin.HasValue || profile.DesiredFundingMax.HasValue ? 1 : 0;
        completed += profile.Languages.Count > 0 ? 1 : 0;
        return completed * 10m;
    }

    private static Dictionary<string, string[]> Validate(
        OrganizationProfileData profile,
        bool requireCollections)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(profile.Name) || profile.Name.Length > 250)
            errors["name"] = ["El nombre es obligatorio y admite hasta 250 caracteres."];
        if (profile.HomeCountryId <= 0) errors["homeCountryId"] = ["Selecciona un país válido."];
        if (profile.OrganizationTypeId <= 0) errors["organizationTypeId"] = ["Selecciona un tipo válido."];
        if (profile.EstablishedYear is < 1800 || profile.EstablishedYear > DateTime.UtcNow.Year)
            errors["establishedYear"] = ["El año de constitución no es válido."];
        if (profile.PreviousFundingExperience > 2)
            errors["previousFundingExperience"] = ["La experiencia previa no es válida."];
        ValidateRange(profile.AnnualBudgetMin, profile.AnnualBudgetMax, profile.AnnualBudgetCurrency, "annualBudget", errors);
        ValidateRange(profile.DesiredFundingMin, profile.DesiredFundingMax, profile.DesiredFundingCurrency, "desiredFunding", errors);
        ValidateLength(profile.LegalName, 300, "legalName", errors);
        ValidateLength(profile.TaxIdentifier, 50, "taxIdentifier", errors);
        ValidateLength(profile.WebsiteUrl, 2048, "websiteUrl", errors);
        ValidateLength(profile.Description, 2000, "description", errors);
        ValidateLength(profile.ExperienceSummary, 2000, "experienceSummary", errors);
        if (!string.IsNullOrWhiteSpace(profile.WebsiteUrl) &&
            (!Uri.TryCreate(profile.WebsiteUrl, UriKind.Absolute, out var website) ||
             website.Scheme is not ("http" or "https") ||
             string.IsNullOrWhiteSpace(website.Host) ||
             !string.IsNullOrEmpty(website.UserInfo)))
            errors["websiteUrl"] = ["Ingresa un dominio válido, por ejemplo onara.org."];
        _ = requireCollections;
        if (profile.Languages.Any(language => language.Proficiency is < 1 or > 5))
            errors["languages"] = ["El dominio de idioma debe estar entre 1 y 5."];
        return errors;
    }

    private static void ValidateRange(decimal? minimum, decimal? maximum, string? currency, string key,
        IDictionary<string, string[]> errors)
    {
        if (minimum < 0 || maximum < 0 || (minimum.HasValue && maximum.HasValue && maximum < minimum))
            errors[key] = ["El rango monetario no es válido."];
        if ((minimum.HasValue || maximum.HasValue) && string.IsNullOrWhiteSpace(currency))
            errors[$"{key}Currency"] = ["Selecciona una moneda para el rango."];
        if (!minimum.HasValue && !maximum.HasValue && !string.IsNullOrWhiteSpace(currency))
            errors[$"{key}Currency"] = ["No indiques moneda si el rango está vacío."];
    }

    private static void ValidateLength(string? value, int maximum, string key, IDictionary<string, string[]> errors)
    {
        if (value?.Length > maximum) errors[key] = [$"Admite hasta {maximum} caracteres."];
    }

    private static OrganizationProfileData Normalize(OrganizationProfileData profile) => profile with
    {
        Name = Normalize(profile.Name),
        LegalName = NormalizeOptional(profile.LegalName),
        TaxIdentifier = NormalizeOptional(profile.TaxIdentifier),
        WebsiteUrl = NormalizeWebsiteUrl(profile.WebsiteUrl),
        Description = NormalizeOptional(profile.Description),
        ExperienceSummary = NormalizeOptional(profile.ExperienceSummary),
        AnnualBudgetCurrency = NormalizeCurrency(profile.AnnualBudgetCurrency),
        DesiredFundingCurrency = NormalizeCurrency(profile.DesiredFundingCurrency),
        CountryIds = profile.CountryIds.Distinct().Order().ToArray(),
        RegionIds = profile.RegionIds.Distinct().Order().ToArray(),
        CategoryIds = profile.CategoryIds.Distinct().Order().ToArray(),
        BeneficiaryTypeIds = profile.BeneficiaryTypeIds.Distinct().Order().ToArray(),
        ProjectTypeIds = profile.ProjectTypeIds.Distinct().Order().ToArray(),
        TagIds = profile.TagIds.Distinct().Order().ToArray(),
        Languages = profile.Languages.GroupBy(language => language.LanguageId)
            .Select(group => group.Last()).OrderBy(language => language.LanguageId).ToArray()
    };

    private static (string Json, byte[] Hash) CreateSnapshot(OrganizationProfileData profile)
    {
        var json = JsonSerializer.Serialize(profile, SnapshotOptions);
        return (json, SHA256.HashData(Encoding.UTF8.GetBytes(json)));
    }

    private static string Normalize(string value) => value.Trim();
    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string? NormalizeWebsiteUrl(string? value)
    {
        var normalized = NormalizeOptional(value);
        if (normalized is null) return null;

        // A domain is the friendliest input for this form. Persisting a full
        // HTTPS URI keeps links safe and gives every downstream consumer one
        // canonical representation. Explicit non-HTTP schemes remain invalid.
        if (!Uri.TryCreate(normalized, UriKind.Absolute, out var absolute) ||
            string.IsNullOrEmpty(absolute.Scheme))
        {
            normalized = $"https://{normalized}";
        }

        return normalized;
    }
    private static string? NormalizeCurrency(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToUpperInvariant();
}
