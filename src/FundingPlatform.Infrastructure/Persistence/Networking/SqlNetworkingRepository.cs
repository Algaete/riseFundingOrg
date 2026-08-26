using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.Networking;
using FundingPlatform.Core.Networking;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Networking;

public sealed class SqlNetworkingRepository(
    ISqlConnectionFactory connectionFactory) : INetworkingRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true
    };

    public async Task<NetworkingPreference?> GetPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<PreferenceRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Get",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId },
                commandType: CommandType.StoredProcedure, commandTimeout: 15,
                cancellationToken: cancellationToken));
            return row is null ? null : Map(row);
        }
        catch (SqlException exception) when (exception.Number == 54603)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read preference", exception);
        }
    }

    public async Task<NetworkingPreferenceMutation> PutPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, bool isDiscoverable, bool allowRequests,
        byte[]? expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var outcome = await connection.QuerySingleAsync<CodeRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationNetworkingPreference_Put",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    IsDiscoverable = isDiscoverable,
                    AllowRequests = allowRequests,
                    ExpectedRowVersion = expectedRowVersion,
                    NowUtc = nowUtc.UtcDateTime
                },
                commandType: CommandType.StoredProcedure, commandTimeout: 20,
                cancellationToken: cancellationToken));
            var mapped = MapPreferenceOutcome(outcome.Code);
            if (mapped is not (NetworkingMutationOutcome.Created or NetworkingMutationOutcome.Updated))
                return new NetworkingPreferenceMutation(mapped);
            var preference = await GetPreferenceAsync(
                userPublicId, organizationPublicId, cancellationToken);
            return new NetworkingPreferenceMutation(mapped, preference);
        }
        catch (SqlException exception) when (exception.Number is 54603 or 54604)
        {
            return new NetworkingPreferenceMutation(exception.Number == 54604
                ? NetworkingMutationOutcome.Forbidden : NetworkingMutationOutcome.NotFound);
        }
        catch (SqlException exception)
        {
            throw Wrap("write preference", exception);
        }
    }

    public async Task<NetworkDirectoryPage?> SearchDirectoryAsync(
        Guid userPublicId, Guid organizationPublicId, NetworkDirectoryFilters filters,
        CancellationToken cancellationToken)
    {
        var parameters = new DynamicParameters();
        parameters.Add("UserPublicId", userPublicId);
        parameters.Add("OrganizationPublicId", organizationPublicId);
        parameters.Add("Query", filters.Query);
        parameters.Add("PageNumber", filters.PageNumber);
        parameters.Add("PageSize", filters.PageSize);
        parameters.Add("CountryIds", ToIdTable(filters.CountryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_SmallIntIdList"));
        parameters.Add("CategoryIds", ToIdTable(filters.CategoryIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        parameters.Add("ProjectTypeIds", ToIdTable(filters.ProjectTypeIds)
            .AsTableValuedParameter("dbo.FundingPlatform_IntIdList"));
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationNetworkDirectory_Search", parameters,
                commandType: CommandType.StoredProcedure, commandTimeout: 20,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<TotalCountRow>();
            var rows = await reader.ReadAsync<DirectoryRow>();
            return new NetworkDirectoryPage(rows.Select(Map).ToArray(), metadata.TotalCount,
                filters.PageNumber, filters.PageSize);
        }
        catch (SqlException exception) when (exception.Number == 54603)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("search directory", exception);
        }
        catch (JsonException exception)
        {
            throw new NetworkingDataException("read directory contract", -1, exception);
        }
    }

    public async Task<OrganizationConnectionPage?> ListConnectionsAsync(
        Guid userPublicId, Guid organizationPublicId, ConnectionDirection direction,
        OrganizationConnectionStatus? status, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationConnection_List",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    Direction = (byte)direction,
                    Status = status.HasValue ? (byte?)status.Value : null,
                    PageNumber = pageNumber,
                    PageSize = pageSize
                }, commandType: CommandType.StoredProcedure, commandTimeout: 20,
                cancellationToken: cancellationToken));
            var metadata = await reader.ReadSingleAsync<TotalCountRow>();
            var rows = await reader.ReadAsync<ConnectionRow>();
            return new OrganizationConnectionPage(rows.Select(Map).ToArray(), metadata.TotalCount,
                pageNumber, pageSize);
        }
        catch (SqlException exception) when (exception.Number == 54603)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("list connections", exception);
        }
    }

    public async Task<OrganizationConnection?> GetConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleOrDefaultAsync<ConnectionRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationConnection_Get",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    ConnectionPublicId = connectionPublicId
                }, commandType: CommandType.StoredProcedure, commandTimeout: 15,
                cancellationToken: cancellationToken));
            return row is null ? null : Map(row);
        }
        catch (SqlException exception) when (exception.Number == 54603)
        {
            return null;
        }
        catch (SqlException exception)
        {
            throw Wrap("read connection", exception);
        }
    }

    public async Task<OrganizationConnectionMutation> CreateConnectionAsync(
        Guid userPublicId, Guid requesterOrganizationPublicId,
        Guid recipientOrganizationPublicId, Guid? requesterProjectPublicId,
        ConnectionPurpose purpose, string message, byte[] idempotencyKeyHash,
        byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationConnection_Create",
                new
                {
                    UserPublicId = userPublicId,
                    RequesterOrganizationPublicId = requesterOrganizationPublicId,
                    RecipientOrganizationPublicId = recipientOrganizationPublicId,
                    RequesterProjectPublicId = requesterProjectPublicId,
                    PurposeCode = (byte)purpose,
                    Message = message,
                    IdempotencyKeyHash = idempotencyKeyHash,
                    RequestHash = requestHash,
                    NowUtc = nowUtc.UtcDateTime
                }, commandType: CommandType.StoredProcedure, commandTimeout: 30,
                cancellationToken: cancellationToken));
            var outcome = MapConnectionOutcome(row.Code);
            OrganizationConnection? result = null;
            if (row.ConnectionPublicId.HasValue)
                result = await GetConnectionAsync(userPublicId, requesterOrganizationPublicId,
                    row.ConnectionPublicId.Value, cancellationToken);
            return new OrganizationConnectionMutation(outcome, result);
        }
        catch (SqlException exception) when (exception.Number is 54603 or 54604)
        {
            return new OrganizationConnectionMutation(exception.Number == 54604
                ? NetworkingMutationOutcome.Forbidden : NetworkingMutationOutcome.NotFound);
        }
        catch (SqlException exception)
        {
            throw Wrap("create connection", exception);
        }
    }

    public async Task<OrganizationConnectionMutation> ActionConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        OrganizationConnectionStatus action, byte[] expectedRowVersion,
        DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<CodeRow>(new CommandDefinition(
                "dbo.FundingPlatform_usp_OrganizationConnection_Action",
                new
                {
                    UserPublicId = userPublicId,
                    OrganizationPublicId = organizationPublicId,
                    ConnectionPublicId = connectionPublicId,
                    ActionCode = (byte)action,
                    ExpectedRowVersion = expectedRowVersion,
                    NowUtc = nowUtc.UtcDateTime
                }, commandType: CommandType.StoredProcedure, commandTimeout: 20,
                cancellationToken: cancellationToken));
            var outcome = MapConnectionOutcome(row.Code);
            var result = outcome == NetworkingMutationOutcome.Updated
                ? await GetConnectionAsync(userPublicId, organizationPublicId,
                    connectionPublicId, cancellationToken) : null;
            return new OrganizationConnectionMutation(outcome, result);
        }
        catch (SqlException exception) when (exception.Number is 54603 or 54604)
        {
            return new OrganizationConnectionMutation(exception.Number == 54604
                ? NetworkingMutationOutcome.Forbidden : NetworkingMutationOutcome.NotFound);
        }
        catch (SqlException exception)
        {
            throw Wrap("act on connection", exception);
        }
    }

    private static NetworkingPreference Map(PreferenceRow row) => new(row.Exists,
        row.IsDiscoverable, row.AllowRequests, ToUtc(row.CreatedAtUtc), ToUtc(row.UpdatedAtUtc),
        row.RowVersion is null ? null : FormatETag(row.RowVersion));

    private static NetworkDirectoryOrganization Map(DirectoryRow row) => new(
        row.OrganizationPublicId, row.Name, row.Description, row.WebsiteUrl,
        new NetworkCatalogItem<short>(row.HomeCountryId, row.HomeCountryCode, row.HomeCountryName),
        new NetworkCatalogItem<short>(row.OrganizationTypeId, row.OrganizationTypeCode,
            row.OrganizationTypeName),
        row.VisibleProjectCount, row.AllowsRequests, row.ConnectionPublicId,
        (DirectoryConnectionState)row.ConnectionState,
        Deserialize<int>(row.CategoriesJson), Deserialize<int>(row.ProjectTypesJson));

    private static OrganizationConnection Map(ConnectionRow row) => new(
        row.ConnectionPublicId, (ConnectionDirection)row.Direction,
        (OrganizationConnectionStatus)row.Status, (ConnectionPurpose)row.PurposeCode,
        row.Message, row.CounterpartyOrganizationPublicId, row.CounterpartyOrganizationName,
        row.CounterpartyIsPublic, row.RequesterProjectPublicIdSnapshot,
        row.RequesterProjectSlugSnapshot, row.RequesterProjectTitleSnapshot,
        row.CanRespond, row.CanCancel, row.CanBlock, ToUtc(row.CreatedAtUtc),
        ToUtc(row.UpdatedAtUtc), ToUtc(row.ActionedAtUtc), FormatETag(row.RowVersion));

    private static IReadOnlyList<NetworkCatalogItem<T>> Deserialize<T>(string? json) =>
        string.IsNullOrWhiteSpace(json) ? [] :
        JsonSerializer.Deserialize<NetworkCatalogItem<T>[]>(json, JsonOptions) ?? [];

    private static NetworkingMutationOutcome MapPreferenceOutcome(string code) => code switch
    {
        "created" => NetworkingMutationOutcome.Created,
        "updated" => NetworkingMutationOutcome.Updated,
        "precondition-required" => NetworkingMutationOutcome.PreconditionRequired,
        "etag-conflict" => NetworkingMutationOutcome.PreconditionFailed,
        _ => NetworkingMutationOutcome.ValidationFailed
    };

    private static NetworkingMutationOutcome MapConnectionOutcome(string code) => code switch
    {
        "created" => NetworkingMutationOutcome.Created,
        "replayed" => NetworkingMutationOutcome.Replay,
        "accepted" or "rejected" or "cancelled" or "blocked" => NetworkingMutationOutcome.Updated,
        "not-found" or "project-not-found" => NetworkingMutationOutcome.NotFound,
        "idempotency-conflict" => NetworkingMutationOutcome.IdempotencyConflict,
        "already-exists" => NetworkingMutationOutcome.AlreadyExists,
        "networking-disabled" => NetworkingMutationOutcome.NetworkingDisabled,
        "rate-limit" => NetworkingMutationOutcome.RateLimited,
        "etag-conflict" => NetworkingMutationOutcome.PreconditionFailed,
        "invalid-transition" => NetworkingMutationOutcome.InvalidTransition,
        _ => NetworkingMutationOutcome.ValidationFailed
    };

    private static DataTable ToIdTable<T>(IEnumerable<T> values)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var value in values) table.Rows.Add(value);
        return table;
    }

    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;
    private static string FormatETag(byte[] value) => $"\"{Convert.ToHexString(value)}\"";
    private static NetworkingDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private sealed class PreferenceRow
    {
        public bool Exists { get; init; }
        public bool IsDiscoverable { get; init; }
        public bool AllowRequests { get; init; }
        public DateTime? CreatedAtUtc { get; init; }
        public DateTime? UpdatedAtUtc { get; init; }
        public byte[]? RowVersion { get; init; }
    }

    private sealed class DirectoryRow
    {
        public Guid OrganizationPublicId { get; init; }
        public string Name { get; init; } = "";
        public string? Description { get; init; }
        public string? WebsiteUrl { get; init; }
        public short HomeCountryId { get; init; }
        public string HomeCountryCode { get; init; } = "";
        public string HomeCountryName { get; init; } = "";
        public short OrganizationTypeId { get; init; }
        public string OrganizationTypeCode { get; init; } = "";
        public string OrganizationTypeName { get; init; } = "";
        public int VisibleProjectCount { get; init; }
        public bool AllowsRequests { get; init; }
        public Guid? ConnectionPublicId { get; init; }
        public byte ConnectionState { get; init; }
        public string? CategoriesJson { get; init; }
        public string? ProjectTypesJson { get; init; }
    }

    private sealed class ConnectionRow
    {
        public Guid ConnectionPublicId { get; init; }
        public byte Direction { get; init; }
        public byte Status { get; init; }
        public byte PurposeCode { get; init; }
        public string Message { get; init; } = "";
        public Guid CounterpartyOrganizationPublicId { get; init; }
        public string CounterpartyOrganizationName { get; init; } = "";
        public bool CounterpartyIsPublic { get; init; }
        public Guid? RequesterProjectPublicIdSnapshot { get; init; }
        public string? RequesterProjectSlugSnapshot { get; init; }
        public string? RequesterProjectTitleSnapshot { get; init; }
        public bool CanRespond { get; init; }
        public bool CanCancel { get; init; }
        public bool CanBlock { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public DateTime? ActionedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }

    private sealed class TotalCountRow { public long TotalCount { get; init; } }
    private class CodeRow { public string Code { get; init; } = ""; }
    private sealed class MutationRow : CodeRow { public Guid? ConnectionPublicId { get; init; } }
}
