using OpenTelemetry;
using OpenTelemetry.Logs;

namespace FundingPlatform.Infrastructure.Observability;

/// <summary>
/// Reduces log records to the fields that are safe to export outside the process.
/// This processor must run before every log exporter.
/// </summary>
public sealed class TelemetryLogPrivacyProcessor : BaseProcessor<LogRecord>
{
    public const string ExceptionTypeAttributeName = "ExceptionType";
    public const string RedactedExceptionMessage = "Exception details were redacted.";
    public const string RedactedLogMessage = "Log details were redacted.";

    private const string OriginalFormatAttributeName = "{OriginalFormat}";
    private const int MaximumTemplateLength = 2_048;

    private static readonly HashSet<string> SafeOperationalStringProperties =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "Application",
            "CorrelationId",
            "Environment",
            "EnvironmentName",
            "EventName",
            "FailureType",
            "FunctionName",
            "InvocationId",
            "Operation",
            "OutcomeCode",
            "RequestId",
            "RequestMethod",
            "ResultCode",
            "SourceContext",
            "SpanId",
            "TraceId"
        };

    private static readonly string[] SensitivePropertyNameFragments =
    [
        "authorization",
        "bearer",
        "body",
        "connectionstring",
        "content",
        "cookie",
        "credential",
        "email",
        "header",
        "oauthcode",
        "password",
        "path",
        "payload",
        "query",
        "requesturi",
        "requesturl",
        "sas",
        "secret",
        "token",
        "uri",
        "url"
    ];

    public override void OnEnd(LogRecord data)
    {
        ArgumentNullException.ThrowIfNull(data);

        if (data.Exception is { } exception)
        {
            SanitizeException(data, exception);
            return;
        }

        SanitizeNormalLog(data);
    }

    private static void SanitizeException(LogRecord data, Exception exception)
    {
        var originalType = exception.GetType().FullName ?? exception.GetType().Name;
        data.Attributes =
        [
            new KeyValuePair<string, object?>(ExceptionTypeAttributeName, originalType)
        ];
        data.Body = RedactedExceptionMessage;
        data.FormattedMessage = RedactedExceptionMessage;

        // Deliberately create, but never throw, a replacement. It has no original
        // message, inner exception, stack trace, Data entries or object references.
        data.Exception = new Exception(RedactedExceptionMessage);
    }

    private static void SanitizeNormalLog(LogRecord data)
    {
        var originalAttributes = data.Attributes;
        var template = FindOriginalFormat(originalAttributes);
        var safeTemplate = IsSafeTemplate(template) ? template! : RedactedLogMessage;
        var safeAttributes = new List<KeyValuePair<string, object?>>();

        if (template is not null)
        {
            safeAttributes.Add(new KeyValuePair<string, object?>(
                OriginalFormatAttributeName,
                safeTemplate));
        }

        if (originalAttributes is not null)
        {
            foreach (var attribute in originalAttributes)
            {
                if (IsOriginalFormat(attribute.Key) ||
                    !TryGetSafeAttributeValue(attribute.Key, attribute.Value, out var safeValue))
                {
                    continue;
                }

                safeAttributes.Add(new KeyValuePair<string, object?>(attribute.Key, safeValue));
            }
        }

        // Assigning Attributes also replaces ILogger state when state is present,
        // so the original structured values are no longer visible to exporters.
        data.Attributes = safeAttributes;
        data.Body = safeTemplate;
        data.FormattedMessage = null;
    }

    private static string? FindOriginalFormat(
        IReadOnlyList<KeyValuePair<string, object?>>? attributes)
    {
        if (attributes is null) return null;

        foreach (var attribute in attributes)
        {
            if (IsOriginalFormat(attribute.Key) && attribute.Value is string template)
            {
                return template;
            }
        }

        return null;
    }

    private static bool IsOriginalFormat(string key) =>
        string.Equals(key, OriginalFormatAttributeName, StringComparison.Ordinal) ||
        string.Equals(key, "OriginalFormat", StringComparison.Ordinal);

    private static bool TryGetSafeAttributeValue(
        string key,
        object? value,
        out object? safeValue)
    {
        safeValue = null;
        if (!IsSafePropertyKey(key) || value is null) return false;

        var normalizedKey = NormalizePropertyName(key);
        var isSensitiveName = SensitivePropertyNameFragments.Any(
            fragment => normalizedKey.Contains(fragment, StringComparison.Ordinal));

        if (isSensitiveName && !IsSafeAggregate(value, normalizedKey)) return false;

        if (value is bool || IsNumeric(value))
        {
            safeValue = value;
            return true;
        }

        if (value is Guid guid)
        {
            if (isSensitiveName) return false;
            safeValue = guid;
            return true;
        }

        if (value is Enum enumValue &&
            SafeOperationalStringProperties.Contains(key))
        {
            safeValue = enumValue.ToString();
            return IsSafeOperationalToken((string)safeValue);
        }

        if (value is not string text || isSensitiveName) return false;

        if (SafeOperationalStringProperties.Contains(key) && IsSafeOperationalToken(text))
        {
            safeValue = text;
            return true;
        }

        return false;
    }

    private static bool IsSafeAggregate(object value, string normalizedKey) =>
        value is bool && normalizedKey.StartsWith("has", StringComparison.Ordinal) ||
        IsNumeric(value) && normalizedKey.EndsWith("count", StringComparison.Ordinal);

    private static bool IsSafeTemplate(string? template)
    {
        if (string.IsNullOrWhiteSpace(template) || template.Length > MaximumTemplateLength)
        {
            return false;
        }

        foreach (var character in template)
        {
            if (char.IsControl(character)) return false;
        }

        // OriginalFormat is expected to be a source-audited static template. These
        // checks fail closed if a caller accidentally embeds common secret forms.
        return !template.Contains("://", StringComparison.Ordinal) &&
               !template.Contains("Bearer ", StringComparison.OrdinalIgnoreCase) &&
               !template.Contains('@') &&
               !(template.Contains('?') && template.Contains('='));
    }

    private static bool IsSafePropertyKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key) || key.Length > 128) return false;

        foreach (var character in key)
        {
            if (!(char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    private static string NormalizePropertyName(string key)
    {
        Span<char> buffer = stackalloc char[key.Length];
        var length = 0;
        foreach (var character in key)
        {
            if (char.IsAsciiLetterOrDigit(character))
            {
                buffer[length++] = char.ToLowerInvariant(character);
            }
        }

        return new string(buffer[..length]);
    }

    private static bool IsNumeric(object value) => value is
        byte or sbyte or short or ushort or int or uint or long or ulong or
        float or double or decimal or IntPtr or UIntPtr;

    private static bool IsSafeOperationalToken(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 256) return false;

        foreach (var character in value)
        {
            if (!(char.IsAsciiLetterOrDigit(character) ||
                  character is '.' or '_' or '-' or ':' or '+' or '`'))
            {
                return false;
            }
        }

        return true;
    }
}
