using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FundingPlatform.Core.Organizations;
using FundingPlatform.Core.Validation;

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
            [], [], [], [], [], [], [], [], []);
        var errors = Validate(profile);
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
                FieldValidationErrors.Single("organization", "organization-data-invalid", "Los datos de organización no son válidos."));
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
        var errors = Validate(profile);
        if (expectedRowVersion.Length != 8)
        {
            errors.Set("ifMatch", "version-invalid", "If-Match no contiene una versión válida.");
        }

        if (errors.Count == 0 && profile.CustomTaxonomyValues is { Count: > 0 })
        {
            var catalogs = await repository.GetCatalogsAsync(cancellationToken);
            ValidateCustomTaxonomyAgainstCatalogs(profile.CustomTaxonomyValues, catalogs, errors);
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
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51011)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.Conflict);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51013)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.Conflict);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber is 51006 or 51204)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.NotFound);
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51012)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors:
                FieldValidationErrors.Single("fundingExperienceTypeIds", "funder-types-review", "Revisa los tipos de financiadores seleccionados."));
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber == 51014)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors:
                FieldValidationErrors.Single("customTaxonomyValues", "custom-options-review", "Revisa las opciones personalizadas de la organización."));
        }
        catch (OrganizationDataException exception) when (exception.DatabaseErrorNumber is 51004 or 51007 or 51010 or 547)
        {
            return new OrganizationWriteResult(OrganizationWriteOutcome.ValidationFailed, Errors:
                FieldValidationErrors.Single("profile", "organization-profile-invalid", "El perfil contiene catálogos o relaciones inválidas."));
        }
    }

    public static decimal CalculateCompleteness(OrganizationProfileData profile)
    {
        var completed = 0;
        completed += !string.IsNullOrWhiteSpace(profile.Name) ? 1 : 0;
        completed += profile.HomeCountryId > 0 && profile.OrganizationTypeId > 0 ? 1 : 0;
        completed += profile.LegalEntityTypeId.HasValue && profile.EstablishedYear.HasValue ? 1 : 0;
        completed += !string.IsNullOrWhiteSpace(profile.Description) ? 1 : 0;
        completed += profile.CountryIds?.Count > 0 ? 1 : 0;
        completed += profile.CategoryIds?.Count > 0 || HasCustom(profile, OrganizationCustomTaxonomyKind.ImpactArea) ? 1 : 0;
        completed += profile.BeneficiaryTypeIds?.Count > 0 || HasCustom(profile, OrganizationCustomTaxonomyKind.BeneficiaryType) ? 1 : 0;
        completed += profile.ProjectTypeIds?.Count > 0 || HasCustom(profile, OrganizationCustomTaxonomyKind.ProjectType) ? 1 : 0;
        completed += profile.DesiredFundingMin.HasValue || profile.DesiredFundingMax.HasValue ? 1 : 0;
        completed += profile.Languages?.Count > 0 || HasCustom(profile, OrganizationCustomTaxonomyKind.Language) ? 1 : 0;
        return completed * 10m;
    }

    private static bool HasCustom(OrganizationProfileData profile, OrganizationCustomTaxonomyKind kind) =>
        profile.CustomTaxonomyValues?.Any(value => value.Kind == kind) == true;

    private static FieldValidationErrors Validate(OrganizationProfileData profile)
    {
        var errors = new FieldValidationErrors();
        if (string.IsNullOrWhiteSpace(profile.Name) || profile.Name.Length > 250)
            errors.Set("name", "name-length", "El nombre es obligatorio y admite hasta 250 caracteres.");
        if (profile.HomeCountryId <= 0) errors.Set("homeCountryId", "country-invalid", "Selecciona un país válido.");
        if (profile.OrganizationTypeId <= 0) errors.Set("organizationTypeId", "organization-type-invalid", "Selecciona un tipo válido.");
        if (profile.EstablishedYear is < 1800 || profile.EstablishedYear > DateTime.UtcNow.Year)
            errors.Set("establishedYear", "established-year-invalid", "El año de constitución no es válido.");
        if (profile.PreviousFundingExperience > 2)
            errors.Set("previousFundingExperience", "funding-experience-invalid", "La experiencia previa no es válida.");
        if (profile.FundingExperienceTypeIds is { Count: > 0 } && profile.PreviousFundingExperience != 2)
            errors.Set("fundingExperienceTypeIds", "funding-experience-required", "Selecciona tipos de financiadores solo si la organización tiene experiencia previa.");
        if (profile.FundingExperienceTypeIds is { Count: > 6 })
            errors.Set("fundingExperienceTypeIds", "funder-types-limit", "Selecciona como máximo seis tipos de financiadores.");
        if (profile.FundingExperienceTypeIds?.Any(id => id is < 1 or > 6) == true)
            errors.Set("fundingExperienceTypeIds", "funder-types-invalid", "Uno o más tipos de financiadores no son válidos.");
        ValidateRange(profile.AnnualBudgetMin, profile.AnnualBudgetMax,
            profile.AnnualBudgetCurrency, "annualBudget", errors);
        ValidateRange(profile.DesiredFundingMin, profile.DesiredFundingMax,
            profile.DesiredFundingCurrency, "desiredFunding", errors);
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
            errors.Set("websiteUrl", "website-invalid", "Ingresa un dominio válido, por ejemplo onara.org.");
        if (profile.Languages.Any(language => language.Proficiency is < 1 or > 5))
            errors.Set("languages", "language-proficiency-invalid", "El dominio de idioma debe estar entre 1 y 5.");
        ValidateCustomTaxonomy(profile.CustomTaxonomyValues ?? [], errors);
        return errors;
    }

    private static void ValidateCustomTaxonomy(
        IReadOnlyList<OrganizationCustomTaxonomyValue> values,
        FieldValidationErrors errors)
    {
        if (values.Count > 20)
            errors.Set("customTaxonomyValues", "custom-options-total-limit", "Puedes agregar hasta 20 opciones personalizadas en total.");

        foreach (var group in values.GroupBy(value => value.Kind))
        {
            var field = CustomField(group.Key);
            if (!Enum.IsDefined(group.Key))
            {
                errors.Set("customTaxonomyValues", "custom-option-kind-invalid", "Una dimensión personalizada no es válida.");
                continue;
            }
            if (group.Count() > 5)
                errors.Set(field, "custom-options-section-limit", "Puedes agregar hasta cinco opciones personalizadas en esta sección.");
            if (group.Any(value => value.Name.Length is < 2 or > 100 || value.NormalizedName.Length is < 2 or > 100))
                errors.Set(field, "custom-option-length", "Cada opción debe tener entre 2 y 100 caracteres.");
            if (group.Any(value => value.Name.Any(character => char.GetUnicodeCategory(character) is
                    UnicodeCategory.Control or UnicodeCategory.Format or UnicodeCategory.Surrogate or
                    UnicodeCategory.PrivateUse or UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator)))
                errors.Set(field, "custom-option-characters", "Las opciones contienen caracteres no permitidos.");
            if (group.GroupBy(value => value.NormalizedName, StringComparer.Ordinal).Any(items => items.Count() > 1))
                errors.Set(field, "custom-option-duplicate", "No agregues la misma opción más de una vez.");
        }
    }

    private static void ValidateCustomTaxonomyAgainstCatalogs(
        IReadOnlyList<OrganizationCustomTaxonomyValue> values,
        OrganizationCatalogs catalogs,
        FieldValidationErrors errors)
    {
        foreach (var group in values.GroupBy(value => value.Kind))
        {
            IEnumerable<string> officialNames = group.Key switch
            {
                OrganizationCustomTaxonomyKind.ImpactArea => catalogs.FundingCategories.Select(item => item.Name),
                OrganizationCustomTaxonomyKind.BeneficiaryType => catalogs.BeneficiaryTypes.Select(item => item.Name),
                OrganizationCustomTaxonomyKind.ProjectType => catalogs.ProjectTypes.Select(item => item.Name),
                OrganizationCustomTaxonomyKind.Language => catalogs.Languages.Select(item => item.Name),
                _ => []
            };
            var official = officialNames.Select(NormalizeComparison).ToHashSet(StringComparer.Ordinal);
            if (group.Any(value => official.Contains(value.NormalizedName)))
                errors.Set(CustomField(group.Key), "custom-option-in-catalog", "Esa opción ya existe en el catálogo. Selecciónala en la lista.");
        }
    }

    private static string CustomField(OrganizationCustomTaxonomyKind kind) => kind switch
    {
        OrganizationCustomTaxonomyKind.ImpactArea => "customImpactAreas",
        OrganizationCustomTaxonomyKind.BeneficiaryType => "customBeneficiaryTypes",
        OrganizationCustomTaxonomyKind.ProjectType => "customProjectTypes",
        OrganizationCustomTaxonomyKind.Language => "customLanguages",
        _ => "customTaxonomyValues"
    };

    private static void ValidateRange(decimal? minimum, decimal? maximum, string? currency, string key,
        FieldValidationErrors errors)
    {
        if (minimum < 0)
            errors.Set($"{key}Min", "amount-min-negative", "El monto mínimo no puede ser negativo.");
        if (maximum < 0)
            errors.Set($"{key}Max", "amount-max-negative", "El monto máximo no puede ser negativo.");
        if (minimum >= 0 && maximum >= 0 && maximum < minimum)
            errors.Set($"{key}Max", "amount-range-order", "El monto máximo no puede ser menor al mínimo.");
        if ((minimum.HasValue || maximum.HasValue) && string.IsNullOrWhiteSpace(currency))
            errors.Set($"{key}Currency", "range-currency-required", "Selecciona una moneda para el rango.");
        if (!minimum.HasValue && !maximum.HasValue && !string.IsNullOrWhiteSpace(currency))
            errors.Set($"{key}Currency", "range-currency-without-amount", "No indiques moneda si el rango está vacío.");
        if (!string.IsNullOrWhiteSpace(currency) &&
            (currency.Length != 3 || currency.Any(character => character is < 'A' or > 'Z')))
            errors.Set($"{key}Currency", "currency-invalid", "Selecciona una moneda ISO de tres letras.");
    }

    private static void ValidateLength(string? value, int maximum, string key, FieldValidationErrors errors)
    {
        if (value?.Length > maximum) errors.Set(key, "text-max-length", $"Admite hasta {maximum} caracteres.", max: maximum);
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
        CountryIds = (profile.CountryIds ?? []).Distinct().Order().ToArray(),
        RegionIds = (profile.RegionIds ?? []).Distinct().Order().ToArray(),
        CategoryIds = (profile.CategoryIds ?? []).Distinct().Order().ToArray(),
        BeneficiaryTypeIds = (profile.BeneficiaryTypeIds ?? []).Distinct().Order().ToArray(),
        ProjectTypeIds = (profile.ProjectTypeIds ?? []).Distinct().Order().ToArray(),
        TagIds = (profile.TagIds ?? []).Distinct().Order().ToArray(),
        Languages = (profile.Languages ?? []).OfType<OrganizationLanguage>()
            .GroupBy(language => language.LanguageId)
            .Select(group => group.Last()).OrderBy(language => language.LanguageId).ToArray(),
        FundingExperienceTypeIds = (profile.FundingExperienceTypeIds ?? [])
            .Distinct().Order().ToArray(),
        CustomTaxonomyValues = (profile.CustomTaxonomyValues ?? [])
            .OfType<OrganizationCustomTaxonomyValue>()
            .Select(value =>
            {
                var name = NormalizeCustomDisplay(value.Name);
                return new OrganizationCustomTaxonomyValue(value.Kind, name, NormalizeComparison(name));
            })
            .OrderBy(value => value.Kind)
            .ThenBy(value => value.NormalizedName, StringComparer.Ordinal)
            .ToArray()
    };

    private static (string Json, byte[] Hash) CreateSnapshot(OrganizationProfileData profile)
    {
        var json = JsonSerializer.Serialize(profile, SnapshotOptions);
        return (json, SHA256.HashData(Encoding.UTF8.GetBytes(json)));
    }

    private static string Normalize(string? value) => value?.Trim() ?? string.Empty;
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

    private static string NormalizeCustomDisplay(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var source = value.Normalize(NormalizationForm.FormKC);
        var builder = new StringBuilder(source.Length);
        var pendingSpace = false;
        foreach (var character in source)
        {
            if (char.IsWhiteSpace(character))
            {
                pendingSpace = builder.Length > 0;
                continue;
            }
            if (pendingSpace) builder.Append(' ');
            pendingSpace = false;
            builder.Append(character);
        }
        return builder.ToString();
    }

    private static string NormalizeComparison(string? value)
    {
        var display = NormalizeCustomDisplay(value);
        var decomposed = display.Normalize(NormalizationForm.FormKD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var character in decomposed)
        {
            var category = char.GetUnicodeCategory(character);
            if (category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or
                UnicodeCategory.EnclosingMark) continue;
            builder.Append(char.ToUpperInvariant(character));
        }
        return builder.ToString().Normalize(NormalizationForm.FormKC);
    }
}
