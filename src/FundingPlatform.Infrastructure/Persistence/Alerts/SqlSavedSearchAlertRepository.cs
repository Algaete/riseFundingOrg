using System.Data;
using Dapper;
using FundingPlatform.Application.Alerts;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Core.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Alerts;

public sealed class SqlSavedSearchAlertRepository(
    ISqlConnectionFactory connectionFactory) : ISavedSearchAlertRepository
{
    private const int NotFoundError = 54503;

    public async Task<SavedSearchPage?> ListSavedSearchesAsync(
        Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(Command(
                "dbo.FundingPlatform_usp_SavedSearch_List",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                      PageNumber = pageNumber, PageSize = pageSize }, cancellationToken));
            var total = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<SavedSearchListRow>()).AsList();
            return new SavedSearchPage(rows.Select(MapSummary).ToArray(), total, pageNumber, pageSize);
        }
        catch (SqlException exception) when (exception.Number == NotFoundError) { return null; }
        catch (SqlException exception) { throw Wrap("list saved searches", exception); }
    }

    public async Task<SavedSearchDetails?> GetSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(Command(
                "dbo.FundingPlatform_usp_SavedSearch_Get",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                      SavedSearchPublicId = savedSearchPublicId }, cancellationToken));
            var row = await reader.ReadSingleOrDefaultAsync<SavedSearchDetailRow>();
            if (row is null) return null;
            var countries = await ReadIdsAsync<short>(reader);
            var regions = await ReadIdsAsync<int>(reader);
            var categories = await ReadIdsAsync<int>(reader);
            var tags = await ReadIdsAsync<long>(reader);
            var beneficiaries = await ReadIdsAsync<int>(reader);
            var projectTypes = await ReadIdsAsync<int>(reader);
            var fundingTypes = await ReadIdsAsync<short>(reader);
            var organizationTypes = await ReadIdsAsync<short>(reader);
            var funders = await ReadIdsAsync<Guid>(reader);
            var filters = new FundingOpportunitySearchFilters(
                row.QueryText, row.SponsorText, row.MinAmount, row.MaxAmount,
                row.Currency?.Trim(), ToDateOnly(row.ClosingFrom), ToDateOnly(row.ClosingTo),
                row.OnlyOpen, (FundingOpportunitySearchSort)row.SortCode, 1, 20,
                countries, regions, categories, tags, beneficiaries, projectTypes,
                fundingTypes, organizationTypes, funders);
            return new SavedSearchDetails(
                row.SavedSearchPublicId, row.Name, filters, MapAlert(row),
                ToUtc(row.CreatedAtUtc), ToUtc(row.UpdatedAtUtc), FormatETag(row.RowVersion));
        }
        catch (SqlException exception) when (exception.Number == NotFoundError) { return null; }
        catch (SqlException exception) { throw Wrap("get saved search", exception); }
    }

    public Task<SavedSearchMutation> CreateSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, string name,
        FundingOpportunitySearchFilters filters, byte[] idempotencyKeyHash,
        byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        MutateSavedSearchAsync(
            "dbo.FundingPlatform_usp_SavedSearch_Create", "create saved search",
            userPublicId, organizationPublicId, null, name, filters, null,
            idempotencyKeyHash, requestHash, nowUtc, cancellationToken);

    public Task<SavedSearchMutation> UpdateSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        string name, FundingOpportunitySearchFilters filters, byte[] expectedRowVersion,
        DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        MutateSavedSearchAsync(
            "dbo.FundingPlatform_usp_SavedSearch_Update", "update saved search",
            userPublicId, organizationPublicId, savedSearchPublicId, name, filters,
            expectedRowVersion, null, null, nowUtc, cancellationToken);

    public async Task<SavedSearchMutation> DeleteSavedSearchAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte[] expectedRowVersion, DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(Command(
                "dbo.FundingPlatform_usp_SavedSearch_Delete",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                      SavedSearchPublicId = savedSearchPublicId,
                      ExpectedRowVersion = expectedRowVersion, NowUtc = Utc(nowUtc) },
                cancellationToken));
            return new SavedSearchMutation(MapSavedSearchOutcome(row.Code));
        }
        catch (SqlException exception) { throw Wrap("delete saved search", exception); }
    }

    public Task<AlertSubscriptionMutation> PutAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        byte preferredHourLocal, string timeZoneId, DateTimeOffset nextRunAtUtc,
        DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        MutateAlertAsync(
            "dbo.FundingPlatform_usp_AlertSubscription_Put", "put saved-search alert",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                  SavedSearchPublicId = savedSearchPublicId, PreferredHourLocal = preferredHourLocal,
                  TimeZoneId = timeZoneId, NextRunAtUtc = Utc(nextRunAtUtc), NowUtc = Utc(nowUtc) },
            cancellationToken);

    public Task<AlertSubscriptionMutation> DeleteAlertAsync(
        Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        MutateAlertAsync(
            "dbo.FundingPlatform_usp_AlertSubscription_Delete", "delete saved-search alert",
            new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                  SavedSearchPublicId = savedSearchPublicId, NowUtc = Utc(nowUtc) },
            cancellationToken);

    public async Task<AlertSubscriptionMutation> UnsubscribeAsync(
        Guid alertSubscriptionPublicId, Guid unsubscribeNonce,
        DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<MutationRow>(Command(
                "dbo.FundingPlatform_usp_AlertSubscription_Unsubscribe",
                new { AlertSubscriptionPublicId = alertSubscriptionPublicId,
                      UnsubscribeNonce = unsubscribeNonce, NowUtc = Utc(nowUtc) },
                cancellationToken));
            return new AlertSubscriptionMutation(row.Code == "deleted"
                ? AlertSubscriptionMutationOutcome.Deleted
                : AlertSubscriptionMutationOutcome.NotFound);
        }
        catch (SqlException exception) { throw Wrap("unsubscribe alert", exception); }
    }

    public async Task<NotificationLogPage?> ListNotificationLogsAsync(
        Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            using var reader = await connection.QueryMultipleAsync(Command(
                "dbo.FundingPlatform_usp_NotificationLog_List",
                new { UserPublicId = userPublicId, OrganizationPublicId = organizationPublicId,
                      PageNumber = pageNumber, PageSize = pageSize }, cancellationToken));
            var total = await reader.ReadSingleAsync<long>();
            var rows = (await reader.ReadAsync<NotificationRow>()).AsList();
            return new NotificationLogPage(rows.Select(row => new NotificationLogSummary(
                row.NotificationLogPublicId, row.AlertSubscriptionPublicId,
                row.SavedSearchPublicId, row.SavedSearchName,
                (NotificationDeliveryStatus)row.Status, row.ItemCount, row.WasTruncated,
                ToUtc(row.ScheduledForUtc), ToUtc(row.SentAtUtc), row.ErrorCode,
                ToUtc(row.CreatedAtUtc))).ToArray(), total, pageNumber, pageSize);
        }
        catch (SqlException exception) when (exception.Number == NotFoundError) { return null; }
        catch (SqlException exception) { throw Wrap("list notification logs", exception); }
    }

    public async Task<IReadOnlyList<AlertScheduleLease>> ClaimSchedulesAsync(
        Guid leaseOwner, int batchSize, int leaseSeconds, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var rows = await connection.QueryAsync<ScheduleLeaseRow>(Command(
            "dbo.FundingPlatform_usp_AlertSchedule_Claim",
            new { LeaseOwner = leaseOwner, BatchSize = batchSize, LeaseSeconds = leaseSeconds,
                  NowUtc = Utc(nowUtc) }, cancellationToken, 30));
        return rows.Select(row => new AlertScheduleLease(
            row.AlertSubscriptionPublicId, row.LeaseId, ToUtc(row.LeaseUntilUtc),
            ToUtc(row.ScheduledForUtc), row.PreferredHourLocal, row.TimeZoneId)).ToArray();
    }

    public async Task<AlertScheduleMaterialization> MaterializeScheduleAsync(
        Guid alertSubscriptionPublicId, Guid leaseId, DateTimeOffset scheduledForUtc,
        DateTimeOffset nextRunAtUtc, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<MaterializationRow>(Command(
            "dbo.FundingPlatform_usp_AlertSchedule_Materialize",
            new { AlertSubscriptionPublicId = alertSubscriptionPublicId, LeaseId = leaseId,
                  ScheduledForUtc = Utc(scheduledForUtc), NextRunAtUtc = Utc(nextRunAtUtc),
                  NowUtc = Utc(nowUtc) }, cancellationToken, 30));
        return new AlertScheduleMaterialization(
            row.Succeeded, row.Code, row.NotificationLogPublicId,
            row.ItemCount, row.WasTruncated);
    }

    public async Task<AlertDeliveryLease?> ClaimDeliveryAsync(
        Guid leaseOwner, int leaseSeconds, int maximumAttempts, DateTimeOffset nowUtc,
        CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        using var reader = await connection.QueryMultipleAsync(Command(
            "dbo.FundingPlatform_usp_AlertDelivery_Claim",
            new { LeaseOwner = leaseOwner, LeaseSeconds = leaseSeconds,
                  MaximumAttempts = maximumAttempts, NowUtc = Utc(nowUtc) },
            cancellationToken, 30));
        var row = await reader.ReadSingleOrDefaultAsync<DeliveryLeaseRow>();
        var items = (await reader.ReadAsync<DeliveryItemRow>()).AsList();
        if (row is null) return null;
        return new AlertDeliveryLease(
            row.NotificationLogPublicId, row.AlertSubscriptionPublicId, row.LeaseId,
            ToUtc(row.LeaseUntilUtc), row.RecipientEmail, row.RecipientDisplayName,
            row.Locale, row.UnsubscribeNonce, row.SavedSearchName,
            ToUtc(row.ScheduledForUtc), row.AttemptCount,
            items.Select(item => new AlertDeliveryItem(
                item.FundingOpportunityPublicId, item.Slug, item.Title, item.SponsorName,
                ToDateOnly(item.CloseDate), ToUtc(item.CloseAtUtc),
                (FundingDeadlineType)item.DeadlineType,
                (FundingDeadlinePrecision)item.DeadlinePrecision)).ToArray());
    }

    public Task<bool> RenewDeliveryLeaseAsync(
        Guid notificationLogPublicId, Guid leaseId, int leaseSeconds,
        DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        ExecuteBooleanAsync("dbo.FundingPlatform_usp_AlertDelivery_RenewLease",
            new { NotificationLogPublicId = notificationLogPublicId, LeaseId = leaseId,
                  LeaseSeconds = leaseSeconds, NowUtc = Utc(nowUtc) }, cancellationToken);

    public Task<bool> CompleteDeliveryAsync(
        Guid notificationLogPublicId, Guid leaseId, string providerMessageId,
        DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
        ExecuteBooleanAsync("dbo.FundingPlatform_usp_AlertDelivery_Complete",
            new { NotificationLogPublicId = notificationLogPublicId, LeaseId = leaseId,
                  ProviderMessageId = providerMessageId, NowUtc = Utc(nowUtc) }, cancellationToken);

    public Task<bool> FailDeliveryAsync(
        Guid notificationLogPublicId, Guid leaseId, bool deliveryUnknown,
        string errorCode, int retryDelaySeconds, int maximumAttempts, DateTimeOffset nowUtc,
        CancellationToken cancellationToken) =>
        ExecuteBooleanAsync("dbo.FundingPlatform_usp_AlertDelivery_Fail",
            new { NotificationLogPublicId = notificationLogPublicId, LeaseId = leaseId,
                  DeliveryUnknown = deliveryUnknown, ErrorCode = errorCode,
                  RetryDelaySeconds = retryDelaySeconds, MaximumAttempts = maximumAttempts,
                  NowUtc = Utc(nowUtc) }, cancellationToken);

    private async Task<SavedSearchMutation> MutateSavedSearchAsync(
        string procedure, string operation, Guid userPublicId, Guid organizationPublicId,
        Guid? savedSearchPublicId, string name, FundingOpportunitySearchFilters filters,
        byte[]? expectedRowVersion, byte[]? idempotencyKeyHash, byte[]? requestHash,
        DateTimeOffset nowUtc, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var parameters = SearchParameters(userPublicId, organizationPublicId, name, filters);
            if (savedSearchPublicId.HasValue) parameters.Add("SavedSearchPublicId", savedSearchPublicId);
            if (expectedRowVersion is not null) parameters.Add("ExpectedRowVersion", expectedRowVersion);
            if (idempotencyKeyHash is not null) parameters.Add("IdempotencyKeyHash", idempotencyKeyHash);
            if (requestHash is not null) parameters.Add("RequestHash", requestHash);
            parameters.Add("NowUtc", Utc(nowUtc));
            var row = await connection.QuerySingleAsync<MutationRow>(Command(
                procedure, parameters, cancellationToken, 30));
            var outcome = MapSavedSearchOutcome(row.Code);
            if (outcome is SavedSearchMutationOutcome.NotFound or
                SavedSearchMutationOutcome.PreconditionFailed or
                SavedSearchMutationOutcome.IdempotencyConflict)
                return new SavedSearchMutation(outcome);
            var details = await GetSavedSearchAsync(
                userPublicId, organizationPublicId, row.SavedSearchPublicId, cancellationToken);
            return new SavedSearchMutation(outcome, details);
        }
        catch (SqlException exception) when (exception.Number is 54502 or 547)
        {
            return new SavedSearchMutation(SavedSearchMutationOutcome.Invalid);
        }
        catch (SqlException exception) { throw Wrap(operation, exception); }
    }

    private async Task<AlertSubscriptionMutation> MutateAlertAsync(
        string procedure, string operation, object parameters, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        try
        {
            var row = await connection.QuerySingleAsync<AlertMutationRow>(Command(
                procedure, parameters, cancellationToken));
            var outcome = row.Code switch
            {
                "created" => AlertSubscriptionMutationOutcome.Created,
                "updated" => AlertSubscriptionMutationOutcome.Updated,
                "deleted" => AlertSubscriptionMutationOutcome.Deleted,
                "not-found" => AlertSubscriptionMutationOutcome.NotFound,
                _ => throw new InvalidOperationException("SQL returned an unknown alert mutation outcome.")
            };
            return new AlertSubscriptionMutation(outcome, row.AlertSubscriptionPublicId == Guid.Empty
                ? null
                : new AlertSubscriptionDetails(
                    row.AlertSubscriptionPublicId, row.PreferredHourLocal, row.TimeZoneId,
                    ToUtc(row.NextRunAtUtc), ToUtc(row.LastRunAtUtc), row.IsActive,
                    row.DisabledReasonCode, ToUtc(row.CreatedAtUtc), ToUtc(row.UpdatedAtUtc),
                    FormatETag(row.RowVersion)));
        }
        catch (SqlException exception) { throw Wrap(operation, exception); }
    }

    private async Task<bool> ExecuteBooleanAsync(
        string procedure, object parameters, CancellationToken cancellationToken)
    {
        await using var connection = connectionFactory.CreateConnection();
        var row = await connection.QuerySingleAsync<BooleanRow>(Command(
            procedure, parameters, cancellationToken));
        return row.Succeeded;
    }

    private static DynamicParameters SearchParameters(
        Guid userPublicId, Guid organizationPublicId, string name,
        FundingOpportunitySearchFilters filters)
    {
        var values = new DynamicParameters();
        values.Add("UserPublicId", userPublicId);
        values.Add("OrganizationPublicId", organizationPublicId);
        values.Add("Name", name);
        values.Add("QueryText", filters.Query);
        values.Add("SponsorText", filters.Sponsor);
        values.Add("MinAmount", filters.MinimumAmount);
        values.Add("MaxAmount", filters.MaximumAmount);
        values.Add("Currency", filters.Currency);
        values.Add("ClosingFrom", ToDateTime(filters.ClosingFrom));
        values.Add("ClosingTo", ToDateTime(filters.ClosingTo));
        values.Add("OnlyOpen", filters.OnlyOpen);
        values.Add("SortCode", (byte)filters.Sort);
        AddIdTable(values, "CountryIds", filters.CountryIds, "dbo.FundingPlatform_SmallIntIdList");
        AddIdTable(values, "RegionIds", filters.RegionIds, "dbo.FundingPlatform_IntIdList");
        AddIdTable(values, "CategoryIds", filters.CategoryIds, "dbo.FundingPlatform_IntIdList");
        AddIdTable(values, "TagIds", filters.TagIds, "dbo.FundingPlatform_BigIntIdList");
        AddIdTable(values, "BeneficiaryTypeIds", filters.BeneficiaryTypeIds, "dbo.FundingPlatform_IntIdList");
        AddIdTable(values, "ProjectTypeIds", filters.ProjectTypeIds, "dbo.FundingPlatform_IntIdList");
        AddIdTable(values, "FundingTypeIds", filters.FundingTypeIds, "dbo.FundingPlatform_SmallIntIdList");
        AddIdTable(values, "OrganizationTypeIds", filters.OrganizationTypeIds, "dbo.FundingPlatform_SmallIntIdList");
        AddIdTable(values, "FunderPublicIds", filters.FunderPublicIds, "dbo.FundingPlatform_GuidIdList");
        return values;
    }

    private static void AddIdTable<T>(DynamicParameters values, string name,
        IEnumerable<T> ids, string typeName)
    {
        var table = new DataTable();
        table.Columns.Add("Id", typeof(T));
        foreach (var id in ids) table.Rows.Add(id);
        values.Add(name, table.AsTableValuedParameter(typeName));
    }

    private static async Task<T[]> ReadIdsAsync<T>(SqlMapper.GridReader reader) =>
        (await reader.ReadAsync<IdRow<T>>()).Select(row => row.Id).ToArray();

    private static SavedSearchSummary MapSummary(SavedSearchListRow row) => new(
        row.SavedSearchPublicId, row.Name, row.QueryText, row.OnlyOpen,
        (FundingOpportunitySearchSort)row.SortCode, row.HasActiveAlert,
        ToUtc(row.CreatedAtUtc), ToUtc(row.UpdatedAtUtc), FormatETag(row.RowVersion));

    private static AlertSubscriptionDetails? MapAlert(SavedSearchDetailRow row) =>
        row.AlertSubscriptionPublicId.HasValue
            ? new AlertSubscriptionDetails(
                row.AlertSubscriptionPublicId.Value, row.PreferredHourLocal!.Value,
                row.TimeZoneId!, ToUtc(row.NextRunAtUtc!.Value), ToUtc(row.LastRunAtUtc),
                row.IsActive!.Value, row.DisabledReasonCode,
                ToUtc(row.AlertCreatedAtUtc!.Value), ToUtc(row.AlertUpdatedAtUtc!.Value),
                FormatETag(row.AlertRowVersion!))
            : null;

    private static SavedSearchMutationOutcome MapSavedSearchOutcome(string code) => code switch
    {
        "created" => SavedSearchMutationOutcome.Created,
        "updated" => SavedSearchMutationOutcome.Updated,
        "deleted" => SavedSearchMutationOutcome.Deleted,
        "replayed" => SavedSearchMutationOutcome.Replay,
        "not-found" => SavedSearchMutationOutcome.NotFound,
        "etag-conflict" => SavedSearchMutationOutcome.PreconditionFailed,
        "idempotency-conflict" => SavedSearchMutationOutcome.IdempotencyConflict,
        _ => throw new InvalidOperationException("SQL returned an unknown saved-search mutation outcome.")
    };

    private static CommandDefinition Command(
        string procedure, object? parameters, CancellationToken cancellationToken,
        int timeout = 15) => new(procedure, parameters, commandType: CommandType.StoredProcedure,
            commandTimeout: timeout, cancellationToken: cancellationToken);
    private static DateTime Utc(DateTimeOffset value) => value.UtcDateTime;
    private static DateTime? ToDateTime(DateOnly? value) => value?.ToDateTime(TimeOnly.MinValue);
    private static DateOnly? ToDateOnly(DateTime? value) =>
        value.HasValue ? DateOnly.FromDateTime(value.Value) : null;
    private static DateTimeOffset ToUtc(DateTime value) =>
        new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
    private static DateTimeOffset? ToUtc(DateTime? value) =>
        value.HasValue ? ToUtc(value.Value) : null;
    private static string FormatETag(byte[] value) => $"\"{Convert.ToHexString(value)}\"";
    private static SavedSearchAlertDataException Wrap(string operation, SqlException exception) =>
        new(operation, exception.Number, exception);

    private class SavedSearchListRow
    {
        public Guid SavedSearchPublicId { get; init; }
        public string Name { get; init; } = "";
        public string? QueryText { get; init; }
        public bool OnlyOpen { get; init; }
        public byte SortCode { get; init; }
        public bool HasActiveAlert { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }
    private sealed class SavedSearchDetailRow : SavedSearchListRow
    {
        public string? SponsorText { get; init; }
        public decimal? MinAmount { get; init; }
        public decimal? MaxAmount { get; init; }
        public string? Currency { get; init; }
        public DateTime? ClosingFrom { get; init; }
        public DateTime? ClosingTo { get; init; }
        public Guid? AlertSubscriptionPublicId { get; init; }
        public byte? PreferredHourLocal { get; init; }
        public string? TimeZoneId { get; init; }
        public DateTime? NextRunAtUtc { get; init; }
        public DateTime? LastRunAtUtc { get; init; }
        public bool? IsActive { get; init; }
        public string? DisabledReasonCode { get; init; }
        public DateTime? AlertCreatedAtUtc { get; init; }
        public DateTime? AlertUpdatedAtUtc { get; init; }
        public byte[]? AlertRowVersion { get; init; }
    }
    private sealed class IdRow<T> { public T Id { get; init; } = default!; }
    private sealed class MutationRow
    {
        public string Code { get; init; } = "";
        public Guid SavedSearchPublicId { get; init; }
    }
    private sealed class AlertMutationRow
    {
        public string Code { get; init; } = "";
        public Guid AlertSubscriptionPublicId { get; init; }
        public byte PreferredHourLocal { get; init; }
        public string TimeZoneId { get; init; } = "";
        public DateTime NextRunAtUtc { get; init; }
        public DateTime? LastRunAtUtc { get; init; }
        public bool IsActive { get; init; }
        public string? DisabledReasonCode { get; init; }
        public DateTime CreatedAtUtc { get; init; }
        public DateTime UpdatedAtUtc { get; init; }
        public byte[] RowVersion { get; init; } = [];
    }
    private sealed class NotificationRow
    {
        public Guid NotificationLogPublicId { get; init; }
        public Guid? AlertSubscriptionPublicId { get; init; }
        public Guid? SavedSearchPublicId { get; init; }
        public string? SavedSearchName { get; init; }
        public byte Status { get; init; }
        public int ItemCount { get; init; }
        public bool WasTruncated { get; init; }
        public DateTime ScheduledForUtc { get; init; }
        public DateTime? SentAtUtc { get; init; }
        public string? ErrorCode { get; init; }
        public DateTime CreatedAtUtc { get; init; }
    }
    private sealed class ScheduleLeaseRow
    {
        public Guid AlertSubscriptionPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public DateTime LeaseUntilUtc { get; init; }
        public DateTime ScheduledForUtc { get; init; }
        public byte PreferredHourLocal { get; init; }
        public string TimeZoneId { get; init; } = "";
    }
    private sealed class MaterializationRow
    {
        public bool Succeeded { get; init; }
        public string Code { get; init; } = "";
        public Guid NotificationLogPublicId { get; init; }
        public int ItemCount { get; init; }
        public bool WasTruncated { get; init; }
    }
    private sealed class DeliveryLeaseRow
    {
        public Guid NotificationLogPublicId { get; init; }
        public Guid AlertSubscriptionPublicId { get; init; }
        public Guid LeaseId { get; init; }
        public DateTime LeaseUntilUtc { get; init; }
        public string RecipientEmail { get; init; } = "";
        public string RecipientDisplayName { get; init; } = "";
        public string Locale { get; init; } = "";
        public Guid UnsubscribeNonce { get; init; }
        public string SavedSearchName { get; init; } = "";
        public DateTime ScheduledForUtc { get; init; }
        public int AttemptCount { get; init; }
    }
    private sealed class DeliveryItemRow
    {
        public Guid FundingOpportunityPublicId { get; init; }
        public string Slug { get; init; } = "";
        public string Title { get; init; } = "";
        public string SponsorName { get; init; } = "";
        public DateTime? CloseDate { get; init; }
        public DateTime? CloseAtUtc { get; init; }
        public byte DeadlineType { get; init; }
        public byte DeadlinePrecision { get; init; }
    }
    private sealed class BooleanRow { public bool Succeeded { get; init; } }
}

public sealed class SavedSearchAlertDataException(
    string operation, int databaseErrorNumber, Exception innerException) : Exception(
        $"Saved-search alert operation '{operation}' failed with database error {databaseErrorNumber}.",
        innerException)
{
    public int DatabaseErrorNumber { get; } = databaseErrorNumber;
}
