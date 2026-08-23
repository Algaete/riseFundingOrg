namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public static class SolutionRootLocator
{
    public const string SolutionFileName = "FundingPlatform.sln";

    public static string Find(string? startDirectory = null)
    {
        var current = new DirectoryInfo(Path.GetFullPath(
            startDirectory ?? Directory.GetCurrentDirectory()));

        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, SolutionFileName)))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        throw new MigrationException("solution_root_not_found");
    }
}
