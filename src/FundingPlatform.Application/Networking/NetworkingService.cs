using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using FundingPlatform.Core.Networking;

namespace FundingPlatform.Application.Networking;

public interface INetworkingRepository
{
    Task<NetworkingPreference?> GetPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, CancellationToken cancellationToken);
    Task<NetworkingPreferenceMutation> PutPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, bool isDiscoverable, bool allowRequests,
        byte[]? expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<NetworkDirectoryPage?> SearchDirectoryAsync(
        Guid userPublicId, Guid organizationPublicId, NetworkDirectoryFilters filters,
        CancellationToken cancellationToken);
    Task<OrganizationConnectionPage?> ListConnectionsAsync(
        Guid userPublicId, Guid organizationPublicId, ConnectionDirection direction,
        OrganizationConnectionStatus? status, int pageNumber, int pageSize,
        CancellationToken cancellationToken);
    Task<OrganizationConnection?> GetConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        CancellationToken cancellationToken);
    Task<OrganizationConnectionMutation> CreateConnectionAsync(
        Guid userPublicId, Guid requesterOrganizationPublicId,
        Guid recipientOrganizationPublicId, Guid? requesterProjectPublicId,
        ConnectionPurpose purpose, string message, byte[] idempotencyKeyHash,
        byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken);
    Task<OrganizationConnectionMutation> ActionConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        OrganizationConnectionStatus action, byte[] expectedRowVersion,
        DateTimeOffset nowUtc, CancellationToken cancellationToken);
}

public sealed record CreateConnectionCommand(
    Guid UserPublicId,
    Guid OrganizationPublicId,
    Guid RecipientOrganizationPublicId,
    Guid? RequesterProjectPublicId,
    ConnectionPurpose Purpose,
    string Message,
    string? IdempotencyKey);

public sealed class NetworkingService(
    INetworkingRepository repository,
    TimeProvider timeProvider)
{
    public const int MaximumQueryLength = 200;
    public const int MaximumFilterValues = 50;
    public const int MaximumPageNumber = 10_000;
    public const int MaximumPageSize = 50;

    public Task<NetworkingPreference?> GetPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, CancellationToken cancellationToken) =>
        !ValidIdentity(userPublicId, organizationPublicId)
            ? Task.FromResult<NetworkingPreference?>(null)
            : repository.GetPreferenceAsync(userPublicId, organizationPublicId, cancellationToken);

    public async Task<NetworkingPreferenceMutation> PutPreferenceAsync(
        Guid userPublicId, Guid organizationPublicId, bool isDiscoverable,
        bool allowRequests, byte[]? expectedRowVersion, CancellationToken cancellationToken)
    {
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            (!isDiscoverable && allowRequests) ||
            (expectedRowVersion is not null && expectedRowVersion.Length != 8))
            return new NetworkingPreferenceMutation(NetworkingMutationOutcome.ValidationFailed);
        return await repository.PutPreferenceAsync(
            userPublicId, organizationPublicId, isDiscoverable, allowRequests,
            expectedRowVersion, timeProvider.GetUtcNow(), cancellationToken);
    }

    public async Task<(NetworkDirectoryPage? Page, IReadOnlyDictionary<string, string[]>? Errors)>
        SearchDirectoryAsync(
            Guid userPublicId, Guid organizationPublicId, NetworkDirectoryFilters filters,
            CancellationToken cancellationToken)
    {
        var normalized = filters with
        {
            Query = NormalizeOptional(filters.Query),
            CountryIds = filters.CountryIds.Distinct().Order().ToArray(),
            CategoryIds = filters.CategoryIds.Distinct().Order().ToArray(),
            ProjectTypeIds = filters.ProjectTypeIds.Distinct().Order().ToArray()
        };
        var errors = ValidateFilters(userPublicId, organizationPublicId, normalized);
        if (errors.Count > 0) return (null, errors);
        return (await repository.SearchDirectoryAsync(
            userPublicId, organizationPublicId, normalized, cancellationToken), null);
    }

    public Task<OrganizationConnectionPage?> ListConnectionsAsync(
        Guid userPublicId, Guid organizationPublicId, ConnectionDirection direction,
        OrganizationConnectionStatus? status, int pageNumber, int pageSize,
        CancellationToken cancellationToken) =>
        !ValidIdentity(userPublicId, organizationPublicId) || !Enum.IsDefined(direction) ||
        (status.HasValue && !Enum.IsDefined(status.Value)) ||
        pageNumber is < 1 or > MaximumPageNumber || pageSize is < 1 or > MaximumPageSize
            ? Task.FromResult<OrganizationConnectionPage?>(null)
            : repository.ListConnectionsAsync(userPublicId, organizationPublicId,
                direction, status, pageNumber, pageSize, cancellationToken);

    public Task<OrganizationConnection?> GetConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        CancellationToken cancellationToken) =>
        !ValidIdentity(userPublicId, organizationPublicId) || connectionPublicId == Guid.Empty
            ? Task.FromResult<OrganizationConnection?>(null)
            : repository.GetConnectionAsync(
                userPublicId, organizationPublicId, connectionPublicId, cancellationToken);

    public async Task<OrganizationConnectionMutation> CreateConnectionAsync(
        CreateConnectionCommand command, CancellationToken cancellationToken)
    {
        var message = NormalizeMessage(command.Message);
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (!ValidIdentity(command.UserPublicId, command.OrganizationPublicId) ||
            command.RecipientOrganizationPublicId == Guid.Empty ||
            command.RecipientOrganizationPublicId == command.OrganizationPublicId ||
            command.RequesterProjectPublicId == Guid.Empty)
            errors["resource"] = ["Selecciona una organización y un proyecto válidos."];
        if (!Enum.IsDefined(command.Purpose))
            errors["purpose"] = ["Selecciona un propósito permitido."];
        if (!ValidMessage(message))
            errors["message"] = ["Escribe entre 10 y 500 caracteres sin email, teléfono ni enlaces."];
        if (!ValidIdempotencyKey(command.IdempotencyKey))
            errors["idempotencyKey"] = ["Idempotency-Key debe tener entre 16 y 128 caracteres ASCII."];
        if (errors.Count > 0)
            return new OrganizationConnectionMutation(
                NetworkingMutationOutcome.ValidationFailed, Errors: errors);

        var requestMaterial = string.Join('\n',
            "organization-connect-v1", command.OrganizationPublicId.ToString("D"),
            command.RecipientOrganizationPublicId.ToString("D"),
            command.RequesterProjectPublicId?.ToString("D") ?? "",
            ((byte)command.Purpose).ToString(CultureInfo.InvariantCulture), message);
        return await repository.CreateConnectionAsync(
            command.UserPublicId, command.OrganizationPublicId,
            command.RecipientOrganizationPublicId, command.RequesterProjectPublicId,
            command.Purpose, message, Hash(command.IdempotencyKey!), Hash(requestMaterial),
            timeProvider.GetUtcNow(), cancellationToken);
    }

    public Task<OrganizationConnectionMutation> ActionConnectionAsync(
        Guid userPublicId, Guid organizationPublicId, Guid connectionPublicId,
        OrganizationConnectionStatus action, byte[]? expectedRowVersion,
        CancellationToken cancellationToken)
    {
        if (!ValidIdentity(userPublicId, organizationPublicId) ||
            connectionPublicId == Guid.Empty || action is < OrganizationConnectionStatus.Accepted
                or > OrganizationConnectionStatus.Blocked || expectedRowVersion?.Length != 8)
            return Task.FromResult(new OrganizationConnectionMutation(
                NetworkingMutationOutcome.ValidationFailed,
                Errors: new Dictionary<string, string[]>
                {
                    ["action"] = ["Acción o ETag no válido."]
                }));
        return repository.ActionConnectionAsync(
            userPublicId, organizationPublicId, connectionPublicId, action,
            expectedRowVersion, timeProvider.GetUtcNow(), cancellationToken);
    }

    private static Dictionary<string, string[]> ValidateFilters(
        Guid userPublicId, Guid organizationPublicId, NetworkDirectoryFilters filters)
    {
        var errors = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);
        if (!ValidIdentity(userPublicId, organizationPublicId))
            errors["resource"] = ["El espacio de networking no existe."];
        if (filters.Query?.Length > MaximumQueryLength)
            errors["q"] = [$"La búsqueda admite hasta {MaximumQueryLength} caracteres."];
        ValidateIds(filters.CountryIds, "countryIds", errors);
        ValidateIds(filters.CategoryIds, "categoryIds", errors);
        ValidateIds(filters.ProjectTypeIds, "projectTypeIds", errors);
        if (filters.PageNumber is < 1 or > MaximumPageNumber)
            errors["page"] = ["La página no es válida."];
        if (filters.PageSize is < 1 or > MaximumPageSize)
            errors["pageSize"] = ["El tamaño de página no es válido."];
        return errors;
    }

    private static void ValidateIds<T>(IReadOnlyCollection<T> values, string key,
        IDictionary<string, string[]> errors) where T : struct, IComparable<T>
    {
        if (values.Count > MaximumFilterValues || values.Any(value => value.CompareTo(default) <= 0))
            errors[key] = [$"Admite hasta {MaximumFilterValues} identificadores positivos."];
    }

    private static bool ValidMessage(string value)
    {
        if (value.Length is < 10 or > 500 || value.Contains('@') ||
            value.Contains("http:", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("https:", StringComparison.OrdinalIgnoreCase) ||
            value.Contains("www.", StringComparison.OrdinalIgnoreCase)) return false;
        var digits = 0;
        foreach (var character in value)
        {
            digits = char.IsDigit(character) ? digits + 1 : 0;
            if (digits >= 8) return false;
        }
        return true;
    }

    private static string NormalizeMessage(string? value) => string.Join(' ',
        (value ?? string.Empty).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static bool ValidIdempotencyKey(string? value) =>
        value is { Length: >= 16 and <= 128 } &&
        value.All(character => character is >= '!' and <= '~');
    private static bool ValidIdentity(Guid userPublicId, Guid organizationPublicId) =>
        userPublicId != Guid.Empty && organizationPublicId != Guid.Empty;
    private static byte[] Hash(string value) => SHA256.HashData(Encoding.UTF8.GetBytes(value));
}

public sealed class NetworkingDataException(
    string operation, int databaseErrorNumber, Exception innerException) : Exception(
        $"Networking operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
