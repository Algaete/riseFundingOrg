using FundingPlatform.Core.Projects;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.Projects;

public static class ProjectEnrichmentRules
{
    public const int MaximumIndicators = 20;
    public const decimal MaximumMeasurement = 1_000_000_000_000m;

    public static ProjectEnrichment? Normalize(ProjectEnrichment? value) => value is null ? null : value with
    {
        Problem = Trim(value.Problem), Solution = Trim(value.Solution),
        Locality = Trim(value.Locality), SoughtPartners = Trim(value.SoughtPartners),
        SoughtProfessionals = Trim(value.SoughtProfessionals),
        ImpactIndicators = value.ImpactIndicators?.Select(item => item is null ? null : item with
        {
            Name = Trim(item.Name), Unit = Trim(item.Unit)
        }).ToArray() ?? []
    };

    public static void Validate(ProjectEnrichment? value, FieldValidationErrors errors)
    {
        if (value is null) return;
        Length(value.Problem, 3000, "problem", errors);
        Length(value.Solution, 3000, "solution", errors);
        Length(value.Locality, 200, "locality", errors);
        Length(value.SoughtPartners, 2000, "soughtPartners", errors);
        Length(value.SoughtProfessionals, 2000, "soughtProfessionals", errors);
        if (value.BeneficiaryCount < 0)
            errors.Set("enrichment.beneficiaryCount", "project-beneficiary-count-invalid", "Indica una cantidad entera de beneficiarios igual o mayor que cero.");
        if (!Enum.IsDefined(value.LocationVisibility))
            errors.Set("enrichment.locationVisibility", "project-location-visibility-invalid", "Selecciona una visibilidad de ubicación válida.");
        if (value.Latitude.HasValue != value.Longitude.HasValue)
            errors.Set("enrichment.latitude", "project-coordinate-pair-required", "Completa latitud y longitud juntas, o deja ambas vacías.");
        if (value.Latitude is < -90 or > 90)
            errors.Set("enrichment.latitude", "project-latitude-invalid", "La latitud debe estar entre -90 y 90.");
        if (value.Longitude is < -180 or > 180)
            errors.Set("enrichment.longitude", "project-longitude-invalid", "La longitud debe estar entre -180 y 180.");
        if (value.LocationVisibility == ProjectLocationVisibility.Locality && value.Locality is null)
            errors.Set("enrichment.locality", "project-locality-required", "Indica la localidad que deseas hacer pública.");
        if (value.LocationVisibility == ProjectLocationVisibility.ApproximatePoint &&
            (!value.Latitude.HasValue || !value.Longitude.HasValue))
            errors.Set("enrichment.latitude", "project-public-point-required", "Indica ambas coordenadas para publicar un punto aproximado.");
        var indicators = value.ImpactIndicators ?? [];
        if (indicators.Count > MaximumIndicators)
            errors.Set("enrichment.impactIndicators", "project-indicators-limit", "Puedes agregar hasta 20 indicadores de impacto.");
        for (var index = 0; index < Math.Min(indicators.Count, MaximumIndicators); index++)
        {
            var item = indicators[index];
            var path = $"impactIndicators.{index}";
            if (string.IsNullOrWhiteSpace(item?.Name) || string.IsNullOrWhiteSpace(item?.Unit))
                errors.Set($"enrichment.{path}", "project-indicator-fields-required", "Cada indicador necesita un nombre y una unidad de medida.");
            if (item is null) continue;
            Length(item.Name, 200, $"{path}.name", errors);
            Length(item.Unit, 80, $"{path}.unit", errors);
            Measurement(item.Baseline, $"{path}.baseline", errors);
            Measurement(item.Target, $"{path}.target", errors);
        }
    }

    private static void Measurement(decimal? value, string path, FieldValidationErrors errors)
    {
        // Negative measurements and decreasing targets are valid (e.g. emissions or temperature).
        if (value is < -MaximumMeasurement or > MaximumMeasurement)
            errors.Set($"enrichment.{path}", "project-indicator-measurement-invalid", "Usa un valor entre -1 billón y 1 billón.");
    }

    private static void Length(string? value, int maximum, string path, FieldValidationErrors errors)
    {
        if (value?.Length > maximum)
            errors.Set($"enrichment.{path}", "text-max-length", $"Admite hasta {maximum} caracteres.", max: maximum);
    }

    private static string? Trim(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
