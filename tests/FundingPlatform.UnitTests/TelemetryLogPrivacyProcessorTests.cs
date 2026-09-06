using FundingPlatform.Infrastructure.Observability;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Logs;

namespace FundingPlatform.UnitTests;

public sealed class TelemetryLogPrivacyProcessorTests
{
    [Fact]
    public void Exception_log_reaches_exporter_without_original_details()
    {
        var exporter = new CapturingLogExporter();
        using var loggerFactory = CreateLoggerFactory(exporter);
        var logger = loggerFactory.CreateLogger("FundingPlatform.Tests");
        var exception = CreateSecretException();

        logger.LogError(
            exception,
            "Request {RequestPath} for {Email} failed with {AccessToken}.",
            "/documents/private-object.pdf",
            "person@example.org",
            "token-secret-123");

        var record = Assert.Single(exporter.Records);
        Assert.Equal(TelemetryLogPrivacyProcessor.RedactedExceptionMessage, record.Body);
        Assert.Equal(TelemetryLogPrivacyProcessor.RedactedExceptionMessage,
            record.FormattedMessage);
        Assert.Equal(typeof(Exception).FullName, record.ExportedExceptionType);
        Assert.Equal(TelemetryLogPrivacyProcessor.RedactedExceptionMessage,
            record.ExportedExceptionMessage);
        Assert.Null(record.ExportedExceptionStackTrace);
        Assert.Null(record.ExportedInnerExceptionMessage);
        Assert.Equal(0, record.ExportedExceptionDataCount);

        var attribute = Assert.Single(record.Attributes);
        Assert.Equal(TelemetryLogPrivacyProcessor.ExceptionTypeAttributeName, attribute.Key);
        Assert.Equal(typeof(InvalidOperationException).FullName, attribute.Value);
        Assert.DoesNotContain("private-object", record.AllText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("person@example.org", record.AllText,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token-secret-123", record.AllText,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("inner-secret", record.AllText,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Normal_log_exports_template_and_only_safe_operational_values()
    {
        var exporter = new CapturingLogExporter();
        using var loggerFactory = CreateLoggerFactory(exporter);
        var logger = loggerFactory.CreateLogger("FundingPlatform.Tests");
        var runId = Guid.NewGuid();
        const string template =
            "Request {RequestPath} for {Email} used {AccessToken}; run={RunId}, " +
            "count={ItemCount}, active={Active}, outcome={OutcomeCode}.";

        using (logger.BeginScope(new Dictionary<string, object?>
               {
                   ["Email"] = "scope-person@example.org"
               }))
        {
            logger.LogInformation(
                template,
                "/documents/private-object.pdf",
                "person@example.org",
                "token-secret-123",
                runId,
                7,
                true,
                "accepted");
        }

        var record = Assert.Single(exporter.Records);
        Assert.Equal(template, record.Body);
        Assert.Null(record.FormattedMessage);
        Assert.Null(record.ExportedExceptionType);
        Assert.Empty(record.Scopes);

        var attributes = record.Attributes.ToDictionary(pair => pair.Key, pair => pair.Value);
        Assert.Equal(template, attributes["{OriginalFormat}"]);
        Assert.Equal(runId, attributes["RunId"]);
        Assert.Equal(7, attributes["ItemCount"]);
        Assert.Equal(true, attributes["Active"]);
        Assert.Equal("accepted", attributes["OutcomeCode"]);
        Assert.DoesNotContain("RequestPath", attributes.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain("Email", attributes.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain("AccessToken", attributes.Keys, StringComparer.OrdinalIgnoreCase);
        Assert.DoesNotContain("private-object", record.AllText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("person@example.org", record.AllText,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("scope-person@example.org", record.AllText,
            StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token-secret-123", record.AllText,
            StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Unreviewed_string_identifiers_are_not_exported_by_suffix_alone()
    {
        var exporter = new CapturingLogExporter();
        using var loggerFactory = CreateLoggerFactory(exporter);
        var logger = loggerFactory.CreateLogger("FundingPlatform.Tests");

        logger.LogInformation("Customer {CustomerId}: count={Count}.",
            "person-private-identifier", 3);

        var record = Assert.Single(exporter.Records);
        Assert.DoesNotContain(record.Attributes, item => item.Key == "CustomerId");
        Assert.Contains(record.Attributes, item => item.Key == "Count" && Equals(item.Value, 3));
        Assert.DoesNotContain("person-private-identifier", record.AllText,
            StringComparison.Ordinal);
    }

    private static ILoggerFactory CreateLoggerFactory(CapturingLogExporter exporter) =>
        LoggerFactory.Create(logging =>
        {
            logging.SetMinimumLevel(LogLevel.Trace);
            logging.AddOpenTelemetry(options =>
            {
                options.IncludeFormattedMessage = true;
                options.IncludeScopes = false;
                options.ParseStateValues = true;
                options.AddProcessor(new TelemetryLogPrivacyProcessor());
                options.AddProcessor(new SimpleLogRecordExportProcessor(exporter));
            });
        });

    private static Exception CreateSecretException()
    {
        try
        {
            throw new InvalidOperationException(
                "token=exception-secret; email=exception-person@example.org",
                new ApplicationException("inner-secret"));
        }
        catch (Exception exception)
        {
            exception.Data["Authorization"] = "Bearer exception-token";
            return exception;
        }
    }

    private sealed class CapturingLogExporter : BaseExporter<LogRecord>
    {
        public List<CapturedLogRecord> Records { get; } = [];

        public override ExportResult Export(in Batch<LogRecord> batch)
        {
            foreach (var record in batch)
            {
                var scopes = new List<string>();
                record.ForEachScope(
                    static (scope, state) => state.Add(scope.ToString() ?? string.Empty),
                    scopes);
                Records.Add(new CapturedLogRecord(
                    record.Body,
                    record.FormattedMessage,
                    record.Exception?.GetType().FullName,
                    record.Exception?.Message,
                    record.Exception?.StackTrace,
                    record.Exception?.InnerException?.Message,
                    record.Exception?.Data.Count ?? 0,
                    record.Attributes?.ToArray() ?? [],
                    scopes));
            }

            return ExportResult.Success;
        }
    }

    private sealed record CapturedLogRecord(
        string? Body,
        string? FormattedMessage,
        string? ExportedExceptionType,
        string? ExportedExceptionMessage,
        string? ExportedExceptionStackTrace,
        string? ExportedInnerExceptionMessage,
        int ExportedExceptionDataCount,
        IReadOnlyList<KeyValuePair<string, object?>> Attributes,
        IReadOnlyList<string> Scopes)
    {
        public string AllText => string.Join(
            "\n",
            new[]
            {
                Body,
                FormattedMessage,
                ExportedExceptionType,
                ExportedExceptionMessage,
                ExportedExceptionStackTrace,
                ExportedInnerExceptionMessage
            }
            .Concat(Attributes.Select(attribute => $"{attribute.Key}={attribute.Value}"))
            .Concat(Scopes)
            .Where(value => value is not null));
    }
}
