using System.Collections;

namespace FundingPlatform.Core.Validation;

// Codes are a public, locale-independent contract. Messages retain compatibility
// with clients that only understand ProblemDetails.errors. Never include input in
// the issue metadata: bounds describe the rule, not the submitted value.
public sealed record FieldValidationIssue(string Code, int? Min = null, int? Max = null);

public sealed class FieldValidationErrors : IReadOnlyDictionary<string, string[]>
{
    private readonly Dictionary<string, (string Message, FieldValidationIssue Issue)> entries =
        new(StringComparer.OrdinalIgnoreCase);

    public void Set(string field, string code, string message, int? min = null, int? max = null) =>
        entries[field] = (message, new FieldValidationIssue(code, min, max));

    public static FieldValidationErrors Single(string field, string code, string message)
    {
        var errors = new FieldValidationErrors();
        errors.Set(field, code, message);
        return errors;
    }

    public IReadOnlyDictionary<string, FieldValidationIssue[]> Issues => entries.ToDictionary(
        entry => entry.Key, entry => new[] { entry.Value.Issue }, StringComparer.OrdinalIgnoreCase);

    public int Count => entries.Count;
    public IEnumerable<string> Keys => entries.Keys;
    public IEnumerable<string[]> Values => entries.Values.Select(entry => new[] { entry.Message });
    public string[] this[string key] => [entries[key].Message];
    public bool ContainsKey(string key) => entries.ContainsKey(key);
    public bool TryGetValue(string key, out string[] value)
    {
        var found = entries.TryGetValue(key, out var entry);
        value = found ? [entry.Message] : [];
        return found;
    }

    public IEnumerator<KeyValuePair<string, string[]>> GetEnumerator() => entries.Select(entry =>
        new KeyValuePair<string, string[]>(entry.Key, [entry.Value.Message])).GetEnumerator();
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
