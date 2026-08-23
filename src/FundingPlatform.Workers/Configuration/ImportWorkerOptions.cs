using Microsoft.Extensions.Options;

namespace FundingPlatform.Workers.Configuration;

public sealed class ImportWorkerOptions
{
    public const string SectionName = "ImportWorkers";

    public int LeaseSeconds { get; set; } = 1800;
    public int SchedulerBatchSize { get; set; } = 10;
    public int OutboxBatchSize { get; set; } = 25;
    public int GrantsGovTimeoutSeconds { get; set; } = 20;
    public string AllowedProviders { get; set; } = "grants-gov";

    public IReadOnlyList<string> GetAllowedProviders() => AllowedProviders
        .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
        .Distinct(StringComparer.Ordinal)
        .ToArray();
}

public sealed class ImportWorkerOptionsValidator : IValidateOptions<ImportWorkerOptions>
{
    public ValidateOptionsResult Validate(string? name, ImportWorkerOptions options)
    {
        var errors = new List<string>();
        if (options.LeaseSeconds != 1800)
        {
            errors.Add(
                "Phase 7A fixes ImportWorkers:LeaseSeconds at 1800 to align SQL lease renewal and queue visibility.");
        }

        if (options.SchedulerBatchSize is < 1 or > 100 ||
            options.OutboxBatchSize is < 1 or > 100)
        {
            errors.Add("Import worker batch sizes must be between 1 and 100.");
        }

        if (options.GrantsGovTimeoutSeconds is < 5 or > 20)
        {
            errors.Add("ImportWorkers:GrantsGovTimeoutSeconds must be between 5 and 20.");
        }

        var allowedProviders = options.GetAllowedProviders();
        var supported = new HashSet<string>(StringComparer.Ordinal)
        {
            "grants-gov",
            "official-rss"
        };
        if (allowedProviders.Count is < 1 or > 2 ||
            !allowedProviders.Contains("grants-gov", StringComparer.Ordinal) ||
            allowedProviders.Any(provider => !supported.Contains(provider)))
        {
            errors.Add("Import providers must be the fixed grants-gov provider and, optionally, governed official-rss.");
        }

        return errors.Count == 0
            ? ValidateOptionsResult.Success
            : ValidateOptionsResult.Fail(errors);
    }
}

public sealed record ImportWorkerIdentity(string LeasePrefix)
{
    public static ImportWorkerIdentity Create() =>
        new($"imports-{Guid.NewGuid():N}");
}
