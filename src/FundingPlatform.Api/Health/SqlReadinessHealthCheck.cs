using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace FundingPlatform.Api.Health;

public sealed class SqlReadinessHealthCheck(SqlConnectionVerifier verifier) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var result = await verifier.CheckAsync(cancellationToken);

        return result.Succeeded
            ? HealthCheckResult.Healthy("Azure SQL responde correctamente.")
            : HealthCheckResult.Unhealthy(
                "Azure SQL no superó la verificación de disponibilidad.",
                data: new Dictionary<string, object>
                {
                    ["code"] = result.Code
                });
    }
}
