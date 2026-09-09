using System.Net;
using System.Reflection;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using FundingPlatform.Application.ProjectAssets;
using FundingPlatform.Application.SourceDocuments;
using FundingPlatform.Core.ProjectAssets;
using FundingPlatform.Workers.Functions;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging.Abstractions;

namespace FundingPlatform.UnitTests;

public sealed class ProjectAssetDefenderEventGridFunctionTests
{
    private const string Topic =
        "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.eventgrid/systemtopics/project-assets";
    private const string SubscriptionName = "project-asset-defender-results";
    private const string Authorization = "Bearer event-grid-token";
    private static readonly DateTimeOffset Now =
        new(2026, 9, 8, 18, 0, 0, TimeSpan.Zero);
    private static readonly Guid AssetId =
        Guid.Parse("11111111-1111-1111-1111-111111111111");

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Missing_or_duplicate_authorization_is_rejected_before_token_validation(
        bool duplicate)
    {
        var fixture = new Fixture();
        var overrides = new Dictionary<string, string[]>
        {
            ["Authorization"] = duplicate ? [Authorization, Authorization] : []
        };

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent(), overrides: overrides),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.Unauthorized,
            "code",
            "event-authentication-required");
        Assert.Equal(0, fixture.Tokens.Calls);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Invalid_bearer_token_is_rejected()
    {
        var fixture = new Fixture(
            tokenValidation: new EventGridTokenValidation(
                EventGridTokenValidationOutcome.Invalid));

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent()),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.Unauthorized,
            "code",
            "event-authentication-required");
        Assert.Equal(1, fixture.Tokens.Calls);
        Assert.Equal(Authorization, fixture.Tokens.AuthorizationHeader);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Token_validation_dependency_failure_returns_service_unavailable()
    {
        var fixture = new Fixture(
            tokenValidation: new EventGridTokenValidation(
                EventGridTokenValidationOutcome.Unavailable));

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent()),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.ServiceUnavailable,
            "code",
            "event-authentication-unavailable");
        Assert.Equal(1, fixture.Tokens.Calls);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Theory]
    [InlineData("aeg-event-type", false)]
    [InlineData("aeg-event-type", true)]
    [InlineData("aeg-subscription-name", false)]
    [InlineData("aeg-subscription-name", true)]
    public async Task Missing_or_duplicate_Event_Grid_headers_are_rejected_before_authentication(
        string headerName,
        bool duplicate)
    {
        var fixture = new Fixture();
        var value = headerName == "aeg-event-type" ? "Notification" : SubscriptionName;
        var overrides = new Dictionary<string, string[]>
        {
            [headerName] = duplicate ? [value, value] : []
        };

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent(), overrides: overrides),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.BadRequest,
            "code",
            "event-request-rejected");
        Assert.Equal(0, fixture.Tokens.Calls);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Payload_larger_than_64_KiB_returns_413_without_dispatching_to_service()
    {
        var fixture = new Fixture();

        var response = await fixture.Function.RunAsync(
            Request(new byte[65_537]),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.RequestEntityTooLarge,
            "code",
            "event-payload-too-large");
        Assert.Equal(1, fixture.Tokens.Calls);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Subscription_validation_handshake_returns_validation_response()
    {
        var fixture = new Fixture();
        var overrides = new Dictionary<string, string[]>
        {
            ["aeg-event-type"] = ["SubscriptionValidation"]
        };

        var response = await fixture.Function.RunAsync(
            Request(ValidationEvent(), overrides: overrides),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.OK,
            "validationResponse",
            "validation-code");
        Assert.Equal(1, fixture.Tokens.Calls);
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Applied_service_outcome_maps_to_200()
    {
        var fixture = new Fixture(
            receiptBehavior: ReceiptBehavior.ReplayApplied);

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent()),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.OK,
            "code",
            "replayed-applied");
        Assert.Equal(1, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Rejected_service_outcome_maps_to_400()
    {
        var fixture = new Fixture();

        var response = await fixture.Function.RunAsync(
            Request("{}"u8.ToArray()),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.BadRequest,
            "code",
            "event-batch-invalid");
        Assert.Equal(0, fixture.Receipts.RecordCalls);
    }

    [Fact]
    public async Task Retry_service_outcome_maps_to_503()
    {
        var fixture = new Fixture(
            receiptBehavior: ReceiptBehavior.DataFailure);

        var response = await fixture.Function.RunAsync(
            Request(NotificationEvent()),
            CancellationToken.None);

        await AssertResponseAsync(
            response,
            HttpStatusCode.ServiceUnavailable,
            "code",
            "scan-receipt-unavailable");
        Assert.Equal(1, fixture.Receipts.RecordCalls);
    }

    private static TestHttpRequestData Request(
        byte[] body,
        IReadOnlyDictionary<string, string[]>? overrides = null)
    {
        var defaults = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["Content-Type"] = ["application/json; charset=utf-8"],
            ["aeg-event-type"] = ["Notification"],
            ["aeg-subscription-name"] = [SubscriptionName],
            ["Authorization"] = [Authorization]
        };
        if (overrides is not null)
        {
            foreach (var (name, values) in overrides)
                defaults[name] = values;
        }

        var headers = defaults
            .Where(entry => entry.Value.Length > 0)
            .Select(entry => new KeyValuePair<string, IEnumerable<string>>(
                entry.Key,
                entry.Value));
        return new TestHttpRequestData(body, new HttpHeadersCollection(headers));
    }

    private static byte[] ValidationEvent() =>
        JsonSerializer.SerializeToUtf8Bytes(new[]
        {
            new
            {
                id = "validation-event",
                topic = Topic,
                eventType = "Microsoft.EventGrid.SubscriptionValidationEvent",
                data = new { validationCode = "validation-code" }
            }
        });

    private static byte[] NotificationEvent()
    {
        var contentHash = SHA256.HashData("project-asset"u8);
        return JsonSerializer.SerializeToUtf8Bytes(new[]
        {
            new
            {
                id = "project-asset-defender-event-1",
                topic = Topic,
                subject =
                    "/storageAccounts/account/containers/fp-project-quarantine/blobs/uploads/test.pdf",
                eventType = "Microsoft.Security.MalwareScanningResult",
                eventTime = Now,
                dataVersion = "1.0",
                data = new
                {
                    blobUri =
                        "https://account.blob.core.windows.net/fp-project-quarantine/uploads/test.pdf",
                    eTag = "0x1",
                    scanResultType = "Malicious",
                    scanFinishedTimeUtc = Now,
                    scanResultDetails = new
                    {
                        sha256 = Convert.ToHexString(contentHash)
                    }
                }
            }
        });
    }

    private static async Task AssertResponseAsync(
        HttpResponseData response,
        HttpStatusCode expectedStatus,
        string propertyName,
        string expectedValue)
    {
        Assert.Equal(expectedStatus, response.StatusCode);
        Assert.True(response.Headers.TryGetValues("Content-Type", out var contentTypes));
        Assert.Equal("application/json; charset=utf-8", Assert.Single(contentTypes));
        Assert.True(response.Headers.TryGetValues("Cache-Control", out var cacheControls));
        Assert.Equal("no-store", Assert.Single(cacheControls));

        response.Body.Position = 0;
        using var json = await JsonDocument.ParseAsync(response.Body);
        Assert.Equal(expectedValue, json.RootElement.GetProperty(propertyName).GetString());
    }

    private sealed class Fixture
    {
        public FakeTokenValidator Tokens { get; }
        public FakeReceiptRepository Receipts { get; }
        public ProjectAssetDefenderEventGridFunction Function { get; }

        public Fixture(
            EventGridTokenValidation? tokenValidation = null,
            ReceiptBehavior receiptBehavior = ReceiptBehavior.Unexpected)
        {
            Tokens = new FakeTokenValidator(tokenValidation ?? new EventGridTokenValidation(
                EventGridTokenValidationOutcome.Valid,
                new EventGridCaller(
                    Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                    Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"))));
            Receipts = new FakeReceiptRepository(receiptBehavior);
            var service = new ProjectAssetDefenderEventGridService(
                Receipts,
                Unused<IProjectAssetRepository>(),
                Unused<IProjectAssetBlobStore>(),
                Unused<IProjectAssetTrustedContentPromoter>(),
                new ProjectAssetDefenderEventGridPolicy(
                    Topic,
                    SubscriptionName,
                    "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourcegroups/rg/providers/microsoft.storage/storageaccounts/account",
                    new Uri("https://account.blob.core.windows.net"),
                    "fp-project-quarantine",
                    "fp-project-trusted",
                    10_485_760,
                    26_214_400,
                    25_000_000,
                    TimeSpan.FromMinutes(5)),
                new FixedTimeProvider(Now));
            Function = new ProjectAssetDefenderEventGridFunction(
                Tokens,
                service,
                NullLogger<ProjectAssetDefenderEventGridFunction>.Instance);
        }
    }

    private enum ReceiptBehavior
    {
        Unexpected,
        ReplayApplied,
        DataFailure
    }

    private sealed class FakeTokenValidator(EventGridTokenValidation validation)
        : IEventGridBearerTokenValidator
    {
        public int Calls { get; private set; }
        public string? AuthorizationHeader { get; private set; }

        public Task<EventGridTokenValidation> ValidateAsync(
            string? authorizationHeader,
            CancellationToken cancellationToken)
        {
            Calls++;
            AuthorizationHeader = authorizationHeader;
            return Task.FromResult(validation);
        }
    }

    private sealed class FakeReceiptRepository(ReceiptBehavior behavior)
        : IProjectAssetDefenderScanReceiptRepository
    {
        public int RecordCalls { get; private set; }

        public Task<ProjectAssetDefenderReceiptWork> RecordAsync(
            string eventGridEventId,
            byte[] payloadHash,
            EventGridCaller caller,
            string eventSubscriptionName,
            string topicResourceId,
            string storageAccountResourceId,
            string blobHost,
            ProtectedProjectAssetBlobLocation quarantineLocation,
            string blobETag,
            byte[]? reportedContentHash,
            ProjectAssetScanStatus status,
            string resultCode,
            DateTimeOffset occurredAtUtc,
            DateTimeOffset receivedAtUtc,
            CancellationToken cancellationToken)
        {
            RecordCalls++;
            return behavior switch
            {
                ReceiptBehavior.ReplayApplied => Task.FromResult(
                    new ProjectAssetDefenderReceiptWork(
                        true,
                        "replayed-applied",
                        Guid.Parse("22222222-2222-2222-2222-222222222222"),
                        AssetId,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        null,
                        false)),
                ReceiptBehavior.DataFailure =>
                    Task.FromException<ProjectAssetDefenderReceiptWork>(
                        new ProjectAssetDataException(
                            "record",
                            -1,
                            new InvalidOperationException("simulated"))),
                _ => Task.FromException<ProjectAssetDefenderReceiptWork>(
                    new InvalidOperationException("Receipt repository was not expected."))
            };
        }

        public Task FinalizeAsync(
            Guid receiptId,
            byte[] payloadHash,
            bool applied,
            string outcomeCode,
            DateTimeOffset finalizedAtUtc,
            CancellationToken cancellationToken) =>
            throw new InvalidOperationException("Finalize was not expected.");
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class TestHttpRequestData : HttpRequestData
    {
        public TestHttpRequestData(byte[] body, HttpHeadersCollection headers)
            : base(new TestFunctionContext())
        {
            Body = new MemoryStream(body, writable: false);
            Headers = headers;
        }

        public override Stream Body { get; }
        public override HttpHeadersCollection Headers { get; }
        public override IReadOnlyCollection<IHttpCookie> Cookies { get; } = [];
        public override Uri Url { get; } =
            new("https://worker.example/api/webhooks/defender-project-assets");
        public override IEnumerable<ClaimsIdentity> Identities { get; } = [];
        public override string Method => "POST";

        public override HttpResponseData CreateResponse() =>
            new TestHttpResponseData(FunctionContext);
    }

    private sealed class TestHttpResponseData : HttpResponseData
    {
        public TestHttpResponseData(FunctionContext functionContext) : base(functionContext)
        {
        }

        public override HttpStatusCode StatusCode { get; set; }
        public override HttpHeadersCollection Headers { get; set; } = new();
        public override Stream Body { get; set; } = new MemoryStream();
        public override HttpCookies Cookies => null!;
    }

    private sealed class TestFunctionContext : FunctionContext
    {
        public override string InvocationId => "test-invocation";
        public override string FunctionId => "test-function";
        public override TraceContext TraceContext => null!;
        public override BindingContext BindingContext => null!;
        public override RetryContext RetryContext => null!;
        public override IServiceProvider InstanceServices { get; set; } = null!;
        public override FunctionDefinition FunctionDefinition => null!;
        public override IDictionary<object, object> Items { get; set; } =
            new Dictionary<object, object>();
        public override IInvocationFeatures Features => null!;
        public override CancellationToken CancellationToken => CancellationToken.None;
    }

    private static T Unused<T>() where T : class =>
        DispatchProxy.Create<T, UnusedProxy>();

    public class UnusedProxy : DispatchProxy
    {
        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) =>
            throw new InvalidOperationException(
                $"Unexpected call to {targetMethod?.DeclaringType?.Name}.{targetMethod?.Name}.");
    }
}
