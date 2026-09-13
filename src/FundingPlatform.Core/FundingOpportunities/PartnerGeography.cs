using System.Text.Json;

namespace FundingPlatform.Core.FundingOpportunities;

// Headquarters of partner organizations, NOT the applicant's eligible project geography.
public enum PartnerGeographyScope : byte { Unknown = 0, Any = 1, Specific = 2 }
public sealed record PartnerGeography(PartnerGeographyScope Scope, IReadOnlyList<int> CountryIds,
    IReadOnlyList<string> RegionCodes, string? CatalogVersion = null);
public sealed record PartnerRegion(string Code, IReadOnlyList<int> CountryIds);

public static class PartnerGeographyCatalog
{
    public const string Version = "partner-geography-2026-09-12";
    public static IReadOnlyList<PartnerRegion> Regions { get; } = ReadRegions();

    public static bool Valid(PartnerGeography geography) =>
        Enum.IsDefined(geography.Scope) && geography.CountryIds is { Count: <= 249 } countries &&
        geography.RegionCodes is { Count: <= 7 } regions && countries.All(id => id is > 0 and <= 999) &&
        countries.Distinct().Count() == countries.Count && regions.Distinct().Count() == regions.Count &&
        regions.All(code => Regions.Any(region => region.Code == code)) &&
        (geography.Scope == PartnerGeographyScope.Specific ? countries.Count + regions.Count > 0 : countries.Count + regions.Count == 0) &&
        (regions.Count == 0 || geography.CatalogVersion == Version);

    private static IReadOnlyList<PartnerRegion> ReadRegions()
    {
        using var stream = typeof(PartnerGeographyCatalog).Assembly.GetManifestResourceStream(
            "FundingPlatform.Core.FundingOpportunities.partner-regions.json")!;
        return JsonSerializer.Deserialize<PartnerRegion[]>(stream, JsonSerializerOptions.Web)!;
    }
}
