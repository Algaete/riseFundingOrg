namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed class RuntimeDatabaseIdentityPlan
{
    public const string ApiRuntimeRole = "FundingPlatform_ApiRuntimeRole";
    public const string GeneralWorkerRole = "FundingPlatform_GeneralWorkerRole";
    public const string ExtractionWorkerRole = "FundingPlatform_ExtractionWorkerRole";

    private RuntimeDatabaseIdentityPlan(
        IReadOnlyList<RuntimeDatabaseIdentity> databaseUsers,
        IReadOnlyList<RuntimeDatabaseAbsentIdentity> identitiesWithoutDatabaseAccess)
    {
        DatabaseUsers = databaseUsers;
        IdentitiesWithoutDatabaseAccess = identitiesWithoutDatabaseAccess;
    }

    public IReadOnlyList<RuntimeDatabaseIdentity> DatabaseUsers { get; }

    public IReadOnlyList<RuntimeDatabaseAbsentIdentity> IdentitiesWithoutDatabaseAccess { get; }

    public static RuntimeDatabaseIdentityPlan Create(
        string apiUserName,
        Guid apiClientId,
        string generalWorkerUserName,
        Guid generalWorkerClientId,
        string extractionConsumerUserName,
        Guid extractionConsumerClientId,
        string extractionHostUserName,
        Guid extractionHostClientId,
        string extractionSenderUserName,
        Guid extractionSenderClientId)
    {
        RuntimeDatabaseIdentity[] databaseUsers =
        [
            new(
                ValidateUserName(apiUserName, nameof(apiUserName)),
                ValidateClientId(apiClientId, nameof(apiClientId)),
                ApiRuntimeRole),
            new(
                ValidateUserName(generalWorkerUserName, nameof(generalWorkerUserName)),
                ValidateClientId(generalWorkerClientId, nameof(generalWorkerClientId)),
                GeneralWorkerRole),
            new(
                ValidateUserName(extractionConsumerUserName, nameof(extractionConsumerUserName)),
                ValidateClientId(extractionConsumerClientId, nameof(extractionConsumerClientId)),
                ExtractionWorkerRole)
        ];
        RuntimeDatabaseAbsentIdentity[] absentIdentities =
        [
            new(
                ValidateUserName(extractionHostUserName, nameof(extractionHostUserName)),
                ValidateClientId(extractionHostClientId, nameof(extractionHostClientId))),
            new(
                ValidateUserName(extractionSenderUserName, nameof(extractionSenderUserName)),
                ValidateClientId(extractionSenderClientId, nameof(extractionSenderClientId)))
        ];

        var allNames = databaseUsers.Select(item => item.UserName)
            .Concat(absentIdentities.Select(item => item.UserName))
            .ToArray();
        if (allNames.Distinct(StringComparer.OrdinalIgnoreCase).Count() != allNames.Length)
        {
            throw new ArgumentException("runtime_identity_user_names_must_be_unique");
        }

        var allClientIds = databaseUsers.Select(item => item.ClientId)
            .Concat(absentIdentities.Select(item => item.ClientId))
            .ToArray();
        if (allClientIds.Distinct().Count() != allClientIds.Length)
        {
            throw new ArgumentException("runtime_identity_client_ids_must_be_unique");
        }

        return new RuntimeDatabaseIdentityPlan(databaseUsers, absentIdentities);
    }

    internal static byte[] ClientIdToSid(Guid clientId) =>
        ValidateClientId(clientId, nameof(clientId)).ToByteArray();

    private static string ValidateUserName(string? value, string parameterName)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.Length > 128 ||
            !string.Equals(value, value.Trim(), StringComparison.Ordinal) ||
            value.Any(character => char.IsControl(character) || char.IsSurrogate(character)))
        {
            throw new ArgumentException("invalid_runtime_database_user_name", parameterName);
        }

        return value;
    }

    private static Guid ValidateClientId(Guid value, string parameterName) =>
        value == Guid.Empty
            ? throw new ArgumentException("invalid_runtime_identity_client_id", parameterName)
            : value;
}

public sealed record RuntimeDatabaseIdentity(string UserName, Guid ClientId, string RoleName);

public sealed record RuntimeDatabaseAbsentIdentity(string UserName, Guid ClientId);
