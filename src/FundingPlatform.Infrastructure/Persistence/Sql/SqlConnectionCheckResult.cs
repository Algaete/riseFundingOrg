namespace FundingPlatform.Infrastructure.Persistence.Sql;

public sealed record SqlConnectionCheckResult(
    bool Succeeded,
    string Code,
    int? SqlErrorNumber = null);
