using System.Data;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.FundingSources;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingSourceAcquisitionAuthorizer(
    ISqlConnectionFactory connectionFactory) : IFundingSourceAcquisitionAuthorizer
{
    public async Task<FundingSourceAcquisitionAuthorization> AuthorizeAsync(
        int fundingSourceId,
        Uri exactDestination,
        byte[] canonicalDestinationHash,
        byte[] acquisitionPolicyFingerprint,
        int minimumIntervalMilliseconds,
        DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        if (fundingSourceId < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(fundingSourceId));
        }

        ValidateDestination(exactDestination);
        if (canonicalDestinationHash is not { Length: 32 } ||
            acquisitionPolicyFingerprint is not { Length: 32 })
            throw new ArgumentException("Acquisition policy hashes must be SHA-256 values.");
        if (minimumIntervalMilliseconds is < 100 or > 60_000)
        {
            throw new ArgumentOutOfRangeException(nameof(minimumIntervalMilliseconds));
        }
        if (nowUtc.Offset != TimeSpan.Zero)
        {
            throw new ArgumentException("The authorization timestamp must be UTC.", nameof(nowUtc));
        }

        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<AuthorizationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingSource_AcquisitionRequest_Authorize",
                new
                {
                    FundingSourceId = fundingSourceId,
                    Scheme = exactDestination.Scheme,
                    HostName = exactDestination.IdnHost.ToLowerInvariant(),
                    Port = exactDestination.Port,
                    CanonicalDestinationHash = canonicalDestinationHash,
                    AcquisitionPolicyFingerprint = acquisitionPolicyFingerprint,
                    MinimumIntervalMilliseconds = minimumIntervalMilliseconds,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure,
                commandTimeout: 15,
                cancellationToken: cancellationToken));

            return new FundingSourceAcquisitionAuthorization(
                row.Allowed,
                NormalizeCode(row.Code),
                ToNullableUtc(row.ReservedAtUtc),
                ToNullableUtc(row.NextAllowedAtUtc),
                row.RetryAfterMilliseconds,
                row.RequestRateLimitPerMinute,
                row.MaximumResponseBytes,
                row.ContentRetentionDays,
                row.AcquisitionPolicyVersion,
                row.AcquisitionPolicyFingerprint);
        }
        catch (SqlException exception)
        {
            throw new FundingSourceImportException(
                "The durable acquisition authorization was unavailable.", exception);
        }
    }

    private static void ValidateDestination(Uri destination)
    {
        ArgumentNullException.ThrowIfNull(destination);
        if (!destination.IsAbsoluteUri || destination.Scheme != Uri.UriSchemeHttps ||
            destination.Port != 443 || !string.IsNullOrEmpty(destination.UserInfo) ||
            !string.IsNullOrEmpty(destination.Fragment) ||
            destination.AbsoluteUri.Length > 2_048 ||
            destination.AbsoluteUri.Contains('\r') ||
            destination.AbsoluteUri.Contains('\n') ||
            destination.AbsoluteUri.Contains('\0') ||
            Uri.CheckHostName(destination.Host) != UriHostNameType.Dns)
        {
            throw new ArgumentException("The acquisition destination is invalid.", nameof(destination));
        }
    }

    private static string NormalizeCode(string? code) => code switch
    {
        "reserved" or "source-disabled" or "compliance-required" or
            "license-required" or "robots-policy-required" or "host-not-allowed" or
            "policy-expired" or "policy-not-found" or "invalid-request" => code,
        _ => "authorization-rejected"
    };

    private static DateTimeOffset? ToNullableUtc(DateTime? value) => value.HasValue
        ? new DateTimeOffset(DateTime.SpecifyKind(value.Value, DateTimeKind.Utc))
        : null;

    private sealed class AuthorizationRow
    {
        public bool Allowed { get; init; }
        public string? Code { get; init; }
        public int? FundingSourceId { get; init; }
        public DateTime? ReservedAtUtc { get; init; }
        public DateTime? NextAllowedAtUtc { get; init; }
        public int? RetryAfterMilliseconds { get; init; }
        public int? RequestRateLimitPerMinute { get; init; }
        public int? MaximumResponseBytes { get; init; }
        public short? ContentRetentionDays { get; init; }
        public int? AcquisitionPolicyVersion { get; init; }
        public byte[]? AcquisitionPolicyFingerprint { get; init; }
    }
}
