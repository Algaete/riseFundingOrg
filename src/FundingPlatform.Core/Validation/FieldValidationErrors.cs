using System.Collections;

namespace FundingPlatform.Core.Validation;

// Codes are a public, locale-independent contract. Messages retain compatibility
// with clients that only understand ProblemDetails.errors. Never include input in
// the issue metadata: bounds describe the rule, not the submitted value.
public sealed record FieldValidationIssue(string Code, long? Min = null, long? Max = null);

public sealed class FieldValidationErrors : IReadOnlyDictionary<string, string[]>
{
    private readonly Dictionary<string, List<(string Message, FieldValidationIssue Issue)>> entries =
        new(StringComparer.OrdinalIgnoreCase);

    public void Set(string field, string code, string message, long? min = null, long? max = null) =>
        entries[field] = [(message, new FieldValidationIssue(code, min, max))];

    public void Add(string field, string code, string message, long? min = null, long? max = null)
    {
        if (!entries.TryGetValue(field, out var values)) entries[field] = values = [];
        if (!values.Any(value => value.Message == message))
            values.Add((message, new FieldValidationIssue(code, min, max)));
    }

    public void Merge(IReadOnlyDictionary<string, string[]> source)
    {
        if (ReferenceEquals(this, source)) return;
        var sourceIssues = (source as FieldValidationErrors)?.Issues;
        foreach (var (field, messages) in source)
        {
            entries.Remove(field);
            var issues = sourceIssues?.GetValueOrDefault(field);
            for (var index = 0; index < messages.Length; index++)
            {
                var issue = issues?.ElementAtOrDefault(index);
                Add(field, issue?.Code ?? "validation-unknown", messages[index], issue?.Min, issue?.Max);
            }
        }
    }

    public static FieldValidationErrors Single(string field, string code, string message)
    {
        var errors = new FieldValidationErrors();
        errors.Set(field, code, message);
        return errors;
    }

    public IReadOnlyDictionary<string, FieldValidationIssue[]> Issues => entries.ToDictionary(
        entry => entry.Key, entry => entry.Value.Select(value => value.Issue).ToArray(), StringComparer.OrdinalIgnoreCase);

    public int Count => entries.Count;
    public bool Remove(string field) => entries.Remove(field);
    public IEnumerable<string> Keys => entries.Keys;
    public IEnumerable<string[]> Values => entries.Values.Select(values => values.Select(value => value.Message).ToArray());
    public string[] this[string key] => entries[key].Select(value => value.Message).ToArray();
    public bool ContainsKey(string key) => entries.ContainsKey(key);
    public bool TryGetValue(string key, out string[] value)
    {
        var found = entries.TryGetValue(key, out var entry);
        value = found ? entry!.Select(item => item.Message).ToArray() : [];
        return found;
    }

    public IEnumerator<KeyValuePair<string, string[]>> GetEnumerator() => entries.Select(entry =>
        new KeyValuePair<string, string[]>(entry.Key, entry.Value.Select(value => value.Message).ToArray())).GetEnumerator();
    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
