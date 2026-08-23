using System.Text.RegularExpressions;

namespace FundingPlatform.Infrastructure.FundingSources.Rss;

internal static class RobotsPolicyEvaluator
{
    public static bool IsAllowed(string content, string userAgent, string path)
    {
        var product = userAgent.Split('/', 2)[0].Trim();
        var groups = new List<Group>();
        Group? current = null;
        foreach (var original in content.Split('\n'))
        {
            var line = original.Split('#', 2)[0].Trim();
            if (line.Length == 0) continue;
            var separator = line.IndexOf(':');
            if (separator <= 0) continue;
            var name = line[..separator].Trim();
            var value = line[(separator + 1)..].Trim();
            if (name.Equals("user-agent", StringComparison.OrdinalIgnoreCase))
            {
                if (current is null || current.HasRules)
                {
                    current = new Group();
                    groups.Add(current);
                }
                current.Agents.Add(value);
            }
            else if (current is not null &&
                     (name.Equals("allow", StringComparison.OrdinalIgnoreCase) ||
                      name.Equals("disallow", StringComparison.OrdinalIgnoreCase)))
            {
                current.Rules.Add(new Rule(
                    name.Equals("allow", StringComparison.OrdinalIgnoreCase), value));
            }
        }

        var matching = groups.Where(group => group.Agents.Any(agent =>
                agent == "*" || product.Equals(agent, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        if (matching.Length == 0) return true;
        var specific = matching.Where(group => group.Agents.Any(agent =>
            product.Equals(agent, StringComparison.OrdinalIgnoreCase))).ToArray();
        var applicable = specific.Length > 0 ? specific : matching;
        var rule = applicable.SelectMany(group => group.Rules)
            .Where(candidate => candidate.Pattern.Length > 0 && candidate.Matches(path))
            .OrderByDescending(candidate => candidate.Specificity)
            .ThenByDescending(candidate => candidate.Allow)
            .FirstOrDefault();
        return rule is null || rule.Allow;
    }

    private sealed class Group
    {
        public List<string> Agents { get; } = [];
        public List<Rule> Rules { get; } = [];
        public bool HasRules => Rules.Count > 0;
    }

    private sealed record Rule(bool Allow, string Pattern)
    {
        public int Specificity => Pattern.Count(character => character is not '*' and not '$');

        public bool Matches(string path)
        {
            // RFC 9309 supports '*' as any sequence and '$' only as an end anchor.
            // Escaping first prevents a robots file from injecting regex syntax.
            var endAnchored = Pattern.EndsWith('$');
            var pattern = endAnchored ? Pattern[..^1] : Pattern;
            var expression = "^" + Regex.Escape(pattern).Replace("\\*", ".*", StringComparison.Ordinal) +
                             (endAnchored ? "$" : string.Empty);
            return Regex.IsMatch(path, expression, RegexOptions.CultureInvariant,
                TimeSpan.FromMilliseconds(50));
        }
    }
}
