using FundingPlatform.Application.Alerts;
using FundingPlatform.Core.Alerts;
using FundingPlatform.Core.FundingOpportunities;

namespace FundingPlatform.UnitTests;

public sealed class SavedSearchAlertTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 8, 25, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Daily_schedule_handles_invalid_and_ambiguous_local_times_conservatively()
    {
        var spring = AlertScheduleCalculator.NextDailyRun(
            new DateTimeOffset(2026, 3, 8, 4, 0, 0, TimeSpan.Zero),
            2,
            "America/New_York");
        var fall = AlertScheduleCalculator.NextDailyRun(
            new DateTimeOffset(2026, 11, 1, 0, 30, 0, TimeSpan.Zero),
            1,
            "America/New_York");

        Assert.Equal(new DateTimeOffset(2026, 3, 8, 7, 0, 0, TimeSpan.Zero), spring);
        Assert.Equal(new DateTimeOffset(2026, 11, 1, 6, 0, 0, TimeSpan.Zero), fall);
        Assert.False(AlertScheduleCalculator.TryFindTimeZone("Unknown/Zone", out _));
    }

    [Fact]
    public void Unsubscribe_token_is_one_purpose_signed_and_tamper_evident()
    {
        var policy = Policy(enabled: true);
        var service = new AlertUnsubscribeTokenService(policy);
        var subscriptionId = Guid.NewGuid();
        var nonce = Guid.NewGuid();

        var token = service.Create(subscriptionId, nonce);

        Assert.True(service.TryValidate(token, out var actualSubscriptionId, out var actualNonce));
        Assert.Equal(subscriptionId, actualSubscriptionId);
        Assert.Equal(nonce, actualNonce);
        var tampered = token[..^1] + (token[^1] == 'A' ? 'B' : 'A');
        Assert.False(service.TryValidate(tampered, out _, out _));
        Assert.False(new AlertUnsubscribeTokenService(Policy(enabled: false))
            .TryValidate(token, out _, out _));
    }

    [Fact]
    public async Task Alert_activation_is_fail_closed_when_delivery_is_disabled()
    {
        var repository = new FakeAlertRepository();
        var service = new SavedSearchAlertService(
            repository, Policy(enabled: false), new FixedTimeProvider(Now));

        var result = await service.PutAlertAsync(
            Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), 8,
            "America/Santiago", CancellationToken.None);

        Assert.Equal(SavedSearchServiceOutcome.AlertsDisabled, result.Outcome);
        Assert.Equal(0, repository.PutAlertCalls);
    }

    [Fact]
    public async Task Saved_search_hash_is_stable_after_filter_normalization()
    {
        var repository = new FakeAlertRepository();
        var service = new SavedSearchAlertService(
            repository, Policy(enabled: false), new FixedTimeProvider(Now));
        var userId = Guid.NewGuid();
        var organizationId = Guid.NewGuid();
        var command = new SavedSearchWriteCommand(
            userId, organizationId, null, "  Fondos de agua  ",
            Filters(countryIds: [152, 56, 152]), "saved-search-test-0001", null);

        var first = await service.CreateAsync(command, CancellationToken.None);
        var second = await service.CreateAsync(command with
        {
            Filters = Filters(countryIds: [56, 152]),
            Name = "Fondos de agua"
        }, CancellationToken.None);

        Assert.Equal(SavedSearchServiceOutcome.Created, first.Outcome);
        Assert.Equal(SavedSearchServiceOutcome.Created, second.Outcome);
        Assert.Equal(2, repository.RequestHashes.Count);
        Assert.Equal(repository.RequestHashes[0], repository.RequestHashes[1]);
        Assert.Equal("Fondos de agua", repository.LastName);
    }

    [Fact]
    public async Task Delivery_renews_before_send_and_persists_provider_receipt()
    {
        var repository = new FakeAlertRepository { Delivery = DeliveryLease() };
        var sender = new FakeEmailSender();
        var service = Processing(repository, sender);

        await service.ProcessDeliveriesAsync(CancellationToken.None);

        Assert.Equal(
            ["claim-delivery", "renew-delivery", "complete-delivery", "claim-delivery"],
            repository.Events);
        Assert.Equal(1, sender.Calls);
        Assert.Equal("provider-message-1", repository.ProviderMessageId);
        Assert.Contains("@", Assert.Single(sender.Messages).RecipientEmail);
        Assert.DoesNotContain("@", Assert.Single(sender.Messages).UnsubscribeToken);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Delivery_failure_distinguishes_safe_retry_from_unknown_outcome(
        bool deliveryUnknown)
    {
        var repository = new FakeAlertRepository { Delivery = DeliveryLease() };
        var sender = new FakeEmailSender
        {
            Exception = new AlertEmailDeliveryException(
                " Provider-Timeout ", deliveryUnknown)
        };

        await Processing(repository, sender).ProcessDeliveriesAsync(CancellationToken.None);

        Assert.Equal(deliveryUnknown, repository.DeliveryUnknown);
        Assert.Equal("provider-timeout", repository.ErrorCode);
        Assert.Equal(30, repository.RetryDelaySeconds);
        Assert.Contains("renew-delivery", repository.Events);
        Assert.Contains("fail-delivery", repository.Events);
        Assert.DoesNotContain("complete-delivery", repository.Events);
    }

    [Fact]
    public async Task Confirmed_delivery_failure_uses_attempt_based_bounded_backoff()
    {
        var repository = new FakeAlertRepository
        {
            Delivery = DeliveryLease() with { AttemptCount = 3 }
        };
        var sender = new FakeEmailSender
        {
            Exception = new AlertEmailDeliveryException("provider-rejected", false)
        };

        await Processing(repository, sender).ProcessDeliveriesAsync(CancellationToken.None);

        Assert.Equal(120, repository.RetryDelaySeconds);
    }

    [Fact]
    public async Task Lost_delivery_lease_stops_before_provider_call()
    {
        var repository = new FakeAlertRepository
        {
            Delivery = DeliveryLease(),
            Renewed = false
        };
        var sender = new FakeEmailSender();

        await Processing(repository, sender).ProcessDeliveriesAsync(CancellationToken.None);

        Assert.Equal(0, sender.Calls);
        Assert.Equal(["claim-delivery", "renew-delivery", "claim-delivery"], repository.Events);
    }

    private static AlertProcessingService Processing(
        FakeAlertRepository repository,
        FakeEmailSender sender) => new(
            repository,
            sender,
            new AlertUnsubscribeTokenService(Policy(enabled: true)),
            Policy(enabled: true),
            new FixedTimeProvider(Now),
            Guid.NewGuid());

    private static AlertProcessingPolicy Policy(bool enabled) => new(
        enabled,
        SchedulerBatchSize: 2,
        ScheduleLeaseSeconds: 120,
        DeliveryLeaseSeconds: 180,
        MaximumAttempts: 3,
        RetryBaseSeconds: 30,
        FrontendBaseUrl: "https://testing.fundingplatform.local",
        UnsubscribeTokenKey: Enumerable.Range(1, 32).Select(value => (byte)value).ToArray());

    private static FundingOpportunitySearchFilters Filters(
        IReadOnlyList<short>? countryIds = null) => new(
            "agua", null, null, null, null, null, null, true,
            FundingOpportunitySearchSort.Relevance, 9, 49,
            countryIds ?? [], [], [], [], [], [], [], [], []);

    private static AlertDeliveryLease DeliveryLease() => new(
        Guid.NewGuid(),
        Guid.NewGuid(),
        Guid.NewGuid(),
        Now.AddMinutes(3),
        "persona@example.org",
        "Persona",
        "es-CL",
        Guid.NewGuid(),
        "Fondos de agua",
        Now,
        1,
        [new AlertDeliveryItem(
            Guid.NewGuid(), "fondo-agua", "Fondo de agua", "Patrocinador",
            new DateOnly(2026, 9, 30), null,
            FundingDeadlineType.Fixed, FundingDeadlinePrecision.Date)]);

    private sealed class FixedTimeProvider(DateTimeOffset value) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => value;
    }

    private sealed class FakeEmailSender : IAlertEmailSender
    {
        public int Calls { get; private set; }
        public List<AlertEmailMessage> Messages { get; } = [];
        public AlertEmailDeliveryException? Exception { get; init; }

        public Task<AlertEmailDeliveryResult> SendAsync(
            AlertEmailMessage message,
            CancellationToken cancellationToken)
        {
            Calls++;
            Messages.Add(message);
            if (Exception is not null) throw Exception;
            return Task.FromResult(new AlertEmailDeliveryResult("provider-message-1"));
        }
    }

    private sealed class FakeAlertRepository : ISavedSearchAlertRepository
    {
        public int PutAlertCalls { get; private set; }
        public string? LastName { get; private set; }
        public List<byte[]> RequestHashes { get; } = [];
        public AlertDeliveryLease? Delivery { get; set; }
        public bool Renewed { get; set; } = true;
        public bool? DeliveryUnknown { get; private set; }
        public string? ErrorCode { get; private set; }
        public int RetryDelaySeconds { get; private set; }
        public string? ProviderMessageId { get; private set; }
        public List<string> Events { get; } = [];

        public Task<SavedSearchPage?> ListSavedSearchesAsync(
            Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken) => Task.FromResult<SavedSearchPage?>(null);

        public Task<SavedSearchDetails?> GetSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            CancellationToken cancellationToken) => Task.FromResult<SavedSearchDetails?>(null);

        public Task<SavedSearchMutation> CreateSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, string name,
            FundingOpportunitySearchFilters filters, byte[] idempotencyKeyHash,
            byte[] requestHash, DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            LastName = name;
            RequestHashes.Add(requestHash);
            return Task.FromResult(new SavedSearchMutation(
                SavedSearchMutationOutcome.Created,
                new SavedSearchDetails(
                    Guid.NewGuid(), name, filters, null, nowUtc, nowUtc,
                    "\"AAAAAAAAAAA=\"")));
        }

        public Task<SavedSearchMutation> UpdateSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            string name, FundingOpportunitySearchFilters filters, byte[] expectedRowVersion,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult(new SavedSearchMutation(SavedSearchMutationOutcome.NotFound));

        public Task<SavedSearchMutation> DeleteSavedSearchAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            byte[] expectedRowVersion, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult(new SavedSearchMutation(SavedSearchMutationOutcome.NotFound));

        public Task<AlertSubscriptionMutation> PutAlertAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            byte preferredHourLocal, string timeZoneId, DateTimeOffset nextRunAtUtc,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            PutAlertCalls++;
            return Task.FromResult(new AlertSubscriptionMutation(
                AlertSubscriptionMutationOutcome.Created));
        }

        public Task<AlertSubscriptionMutation> DeleteAlertAsync(
            Guid userPublicId, Guid organizationPublicId, Guid savedSearchPublicId,
            DateTimeOffset nowUtc, CancellationToken cancellationToken) =>
            Task.FromResult(new AlertSubscriptionMutation(AlertSubscriptionMutationOutcome.Deleted));

        public Task<AlertSubscriptionMutation> UnsubscribeAsync(
            Guid alertSubscriptionPublicId, Guid unsubscribeNonce, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult(new AlertSubscriptionMutation(AlertSubscriptionMutationOutcome.Deleted));

        public Task<NotificationLogPage?> ListNotificationLogsAsync(
            Guid userPublicId, Guid organizationPublicId, int pageNumber, int pageSize,
            CancellationToken cancellationToken) => Task.FromResult<NotificationLogPage?>(null);

        public Task<IReadOnlyList<AlertScheduleLease>> ClaimSchedulesAsync(
            Guid leaseOwner, int batchSize, int leaseSeconds, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<AlertScheduleLease>>([]);

        public Task<AlertScheduleMaterialization> MaterializeScheduleAsync(
            Guid alertSubscriptionPublicId, Guid leaseId, DateTimeOffset scheduledForUtc,
            DateTimeOffset nextRunAtUtc, DateTimeOffset nowUtc,
            CancellationToken cancellationToken) =>
            Task.FromResult(new AlertScheduleMaterialization(true, "created", Guid.NewGuid(), 1, false));

        public Task<AlertDeliveryLease?> ClaimDeliveryAsync(
            Guid leaseOwner, int leaseSeconds, int maximumAttempts, DateTimeOffset nowUtc,
            CancellationToken cancellationToken)
        {
            Events.Add("claim-delivery");
            var value = Delivery;
            Delivery = null;
            return Task.FromResult(value);
        }

        public Task<bool> RenewDeliveryLeaseAsync(
            Guid notificationLogPublicId, Guid leaseId, int leaseSeconds,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            Events.Add("renew-delivery");
            return Task.FromResult(Renewed);
        }

        public Task<bool> CompleteDeliveryAsync(
            Guid notificationLogPublicId, Guid leaseId, string providerMessageId,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            Events.Add("complete-delivery");
            ProviderMessageId = providerMessageId;
            return Task.FromResult(true);
        }

        public Task<bool> FailDeliveryAsync(
            Guid notificationLogPublicId, Guid leaseId, bool deliveryUnknown,
            string errorCode, int retryDelaySeconds, int maximumAttempts,
            DateTimeOffset nowUtc, CancellationToken cancellationToken)
        {
            Events.Add("fail-delivery");
            DeliveryUnknown = deliveryUnknown;
            ErrorCode = errorCode;
            RetryDelaySeconds = retryDelaySeconds;
            return Task.FromResult(true);
        }
    }
}
