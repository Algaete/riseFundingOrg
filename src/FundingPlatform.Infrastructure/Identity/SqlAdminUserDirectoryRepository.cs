using Dapper;
using FundingPlatform.Application.Authentication;
using FundingPlatform.Core.Identity;
using FundingPlatform.Infrastructure.Identity.Persistence;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Identity;

public sealed class SqlAdminUserDirectoryRepository(
    ISqlConnectionFactory connectionFactory) : IAdminUserDirectoryRepository
{
    private const string ListSql = """
        SELECT COUNT_BIG(1)
        FROM dbo.FundingPlatform_Users AS users
        WHERE (@NormalizedQuery IS NULL
               OR CHARINDEX(@NormalizedQuery, users.NormalizedEmail) > 0
               OR CHARINDEX(@Query, users.DisplayName) > 0)
          AND (@Status IS NULL OR users.Status = @Status)
          AND (@NormalizedRole IS NULL OR EXISTS
              (
                  SELECT 1
                  FROM dbo.FundingPlatform_UserRoles AS filteredUserRoles
                  INNER JOIN dbo.FundingPlatform_Roles AS filteredRoles
                      ON filteredRoles.Id = filteredUserRoles.RoleId
                  WHERE filteredUserRoles.UserId = users.Id
                    AND filteredRoles.NormalizedName = @NormalizedRole
              ));

        ;WITH PageUsers AS
        (
            SELECT users.Id,
                   users.PublicId,
                   users.Email,
                   users.DisplayName,
                   users.PreferredLocale,
                   users.Status,
                   users.EmailConfirmed,
                   users.TwoFactorEnabled,
                   users.LastLoginAtUtc,
                   users.CreatedAtUtc
            FROM dbo.FundingPlatform_Users AS users
            WHERE (@NormalizedQuery IS NULL
                   OR CHARINDEX(@NormalizedQuery, users.NormalizedEmail) > 0
                   OR CHARINDEX(@Query, users.DisplayName) > 0)
              AND (@Status IS NULL OR users.Status = @Status)
              AND (@NormalizedRole IS NULL OR EXISTS
                  (
                      SELECT 1
                      FROM dbo.FundingPlatform_UserRoles AS filteredUserRoles
                      INNER JOIN dbo.FundingPlatform_Roles AS filteredRoles
                          ON filteredRoles.Id = filteredUserRoles.RoleId
                      WHERE filteredUserRoles.UserId = users.Id
                        AND filteredRoles.NormalizedName = @NormalizedRole
                  ))
            ORDER BY users.NormalizedEmail, users.Id
            OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
        )
        SELECT pageUsers.PublicId,
               pageUsers.Email,
               pageUsers.DisplayName,
               pageUsers.PreferredLocale,
               pageUsers.Status,
               pageUsers.EmailConfirmed,
               pageUsers.TwoFactorEnabled,
               pageUsers.LastLoginAtUtc,
               pageUsers.CreatedAtUtc,
               roles.Name AS RoleName
        FROM PageUsers AS pageUsers
        LEFT JOIN dbo.FundingPlatform_UserRoles AS userRoles
            ON userRoles.UserId = pageUsers.Id
        LEFT JOIN dbo.FundingPlatform_Roles AS roles
            ON roles.Id = userRoles.RoleId
        ORDER BY pageUsers.Email, pageUsers.Id, roles.Id;
        """;

    public async Task<AdminUserDirectoryPage> ListAsync(
        AdminUserDirectoryQuery query,
        CancellationToken cancellationToken)
    {
        var search = string.IsNullOrWhiteSpace(query.Search) ? null : query.Search.Trim();
        var role = string.IsNullOrWhiteSpace(query.Role) ? null : query.Role.Trim();

        try
        {
            await using var connection = connectionFactory.CreateConnection();
            await connection.OpenAsync(cancellationToken);
            using var reader = await connection.QueryMultipleAsync(new CommandDefinition(
                ListSql,
                new
                {
                    Query = search,
                    NormalizedQuery = search?.ToUpperInvariant(),
                    Status = query.Status is null ? null : (byte?)query.Status.Value,
                    NormalizedRole = role?.ToUpperInvariant(),
                    Offset = checked((query.Page - 1) * query.PageSize),
                    query.PageSize
                },
                commandTimeout: 20,
                cancellationToken: cancellationToken));

            var totalCount = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<UserRow>()).ToArray();
            var items = rows
                .GroupBy(row => row.PublicId)
                .Select(group =>
                {
                    var row = group.First();
                    return new AdminUserDirectoryItem(
                        row.PublicId,
                        row.Email,
                        row.DisplayName,
                        row.PreferredLocale,
                        (UserStatus)row.Status,
                        row.EmailConfirmed,
                        row.TwoFactorEnabled,
                        Utc(row.LastLoginAtUtc),
                        Utc(row.CreatedAtUtc),
                        group.Where(item => !string.IsNullOrWhiteSpace(item.RoleName))
                            .Select(item => item.RoleName!)
                            .Distinct(StringComparer.OrdinalIgnoreCase)
                            .OrderBy(item => item, StringComparer.OrdinalIgnoreCase)
                            .ToArray());
                })
                .ToArray();

            return new AdminUserDirectoryPage(items, totalCount, query.Page, query.PageSize);
        }
        catch (SqlException exception)
        {
            throw new AuthenticationDataException("list_admin_users", exception.Number, exception);
        }
    }

    private static DateTimeOffset Utc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));

    private static DateTimeOffset? Utc(DateTime? value) =>
        value is null ? null : Utc(value.Value);

    private sealed class UserRow
    {
        public Guid PublicId { get; init; }
        public string Email { get; init; } = string.Empty;
        public string DisplayName { get; init; } = string.Empty;
        public string PreferredLocale { get; init; } = string.Empty;
        public byte Status { get; init; }
        public bool EmailConfirmed { get; init; }
        public bool TwoFactorEnabled { get; init; }
        public DateTime? LastLoginAtUtc { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public string? RoleName { get; init; }
    }
}
