using FundingPlatform.Core.Validation;

namespace FundingPlatform.Api.Endpoints;

internal static class FieldValidationResults
{
    // Preserve the existing status, title, type and errors representation. Old
    // dictionaries remain valid; do not guess rule codes from their message text.
    internal static IResult BadRequest(IReadOnlyDictionary<string, string[]> errors) =>
        Results.ValidationProblem(errors, extensions: Extensions(errors));

    internal static Dictionary<string, object?> Extensions(IReadOnlyDictionary<string, string[]>? errors)
    {
        var extensions = new Dictionary<string, object?>();
        if (errors is FieldValidationErrors typed)
            extensions["validationIssues"] = typed.Issues;
        return extensions;
    }
}
