using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Core.Collaboration;
using FundingPlatform.Core.Validation;

namespace FundingPlatform.Application.FundingOpportunities;
public interface IFundingDiscoveryRepository
{
    Task<FundingDiscoveryPage> SearchAsync(FundingDiscoveryFilters filters, CancellationToken token);
    Task<FundingDiscoveryAdmin?> GetAsync(Guid actor, Guid opportunityId, CancellationToken token);
    Task<CollaborationWriteResult> ReviewAsync(Guid actor, Guid opportunityId, FundingDiscoveryReview data, byte[]? version, byte[] keyHash, byte[] requestHash, CancellationToken token);
}
public sealed class FundingDiscoveryDataException(int number, Exception inner) : Exception("Funding discovery operation failed.", inner)
{
    public int Number { get; } = number;
}
public static class FundingDiscoveryRules
{
    public static FieldValidationErrors Validate(FundingDiscoveryFilters filters)
    {
        var errors = new FieldValidationErrors();
        void Invalid(string field) => errors.Set(field, "api-validation-131", "El valor no es válido.");
        if (filters.Query?.Length > 300) Invalid("query");
        if (filters.Page is < 1 or > 10000 || filters.PageSize is < 1 or > 50) Invalid("pagination");
        if (filters.CountryId is <= 0 || filters.RegionId is <= 0 || filters.CategoryId is <= 0 || filters.FundingTypeId is <= 0 || filters.OrganizationTypeId is <= 0 || filters.LanguageId is <= 0 || filters.FunderKind is < 1 or > 6) Invalid("filters");
        if (filters.MinimumAmount is < 0 or > 999999999999m || filters.MaximumAmount is < 0 or > 999999999999m || filters.MinimumAmount > filters.MaximumAmount) Invalid("amount");
        if ((filters.MinimumAmount.HasValue || filters.MaximumAmount.HasValue) && (filters.Currency is null || filters.Currency.Length != 3 || !filters.Currency.All(c => c is >= 'A' and <= 'Z'))) Invalid("currency");
        if (filters.ClosingFrom > filters.ClosingTo) Invalid("deadline");
        return errors;
    }
    public static FieldValidationErrors Validate(FundingDiscoveryReview review)
    {
        var errors = new FieldValidationErrors();
        if (review.ContentVersion < 1 || review.Data is null || review.Data.FunderKind is < 1 or > 6 ||
            !Uri.TryCreate(review.Data.EvidenceUrl, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
            uri.Port != 443 || uri.UserInfo.Length > 0 || uri.Fragment.Length > 0 || uri.AbsoluteUri.Length > 2000)
            errors.Set("classification", "api-validation-131", "Revisa la clasificación y su fuente oficial.");
        if (review.Data?.PartnerGeography is { } geography && !PartnerGeographyCatalog.Valid(geography))
            errors.Set("partnerGeography", "api-validation-131", "Revisa los países y regiones admitidos para los socios.");
        return errors;
    }
}
