namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static class GoBatchSplitter
{
    public static IReadOnlyList<string> Split(string script)
    {
        ArgumentNullException.ThrowIfNull(script);

        var batches = new List<string>();
        var currentBatch = new System.Text.StringBuilder();
        var state = new LexicalState();

        using var reader = new StringReader(script);
        while (reader.ReadLine() is { } line)
        {
            if (state.IsNormal && string.Equals(line.Trim(), "GO", StringComparison.OrdinalIgnoreCase))
            {
                AddBatch(batches, currentBatch);
                continue;
            }

            currentBatch.AppendLine(line);
            state.Scan(line);
        }

        AddBatch(batches, currentBatch);
        return batches;
    }

    private static void AddBatch(List<string> batches, System.Text.StringBuilder batch)
    {
        var sql = batch.ToString().Trim();
        if (sql.Length > 0)
        {
            batches.Add(sql);
        }

        batch.Clear();
    }

    private sealed class LexicalState
    {
        private bool inString;
        private bool inQuotedIdentifier;
        private bool inBracketedIdentifier;
        private int blockCommentDepth;

        public bool IsNormal =>
            !inString && !inQuotedIdentifier && !inBracketedIdentifier && blockCommentDepth == 0;

        public void Scan(string line)
        {
            for (var index = 0; index < line.Length; index++)
            {
                var current = line[index];
                var next = index + 1 < line.Length ? line[index + 1] : '\0';

                if (inString)
                {
                    if (current != '\'')
                    {
                        continue;
                    }

                    if (next == '\'')
                    {
                        index++;
                    }
                    else
                    {
                        inString = false;
                    }

                    continue;
                }

                if (inQuotedIdentifier)
                {
                    if (current != '"')
                    {
                        continue;
                    }

                    if (next == '"')
                    {
                        index++;
                    }
                    else
                    {
                        inQuotedIdentifier = false;
                    }

                    continue;
                }

                if (inBracketedIdentifier)
                {
                    if (current != ']')
                    {
                        continue;
                    }

                    if (next == ']')
                    {
                        index++;
                    }
                    else
                    {
                        inBracketedIdentifier = false;
                    }

                    continue;
                }

                if (blockCommentDepth > 0)
                {
                    if (current == '/' && next == '*')
                    {
                        blockCommentDepth++;
                        index++;
                    }
                    else if (current == '*' && next == '/')
                    {
                        blockCommentDepth--;
                        index++;
                    }

                    continue;
                }

                if (current == '-' && next == '-')
                {
                    return;
                }

                if (current == '/' && next == '*')
                {
                    blockCommentDepth++;
                    index++;
                }
                else if (current == '\'')
                {
                    inString = true;
                }
                else if (current == '"')
                {
                    inQuotedIdentifier = true;
                }
                else if (current == '[')
                {
                    inBracketedIdentifier = true;
                }
            }
        }
    }
}
