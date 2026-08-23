using DotNetEnv;

namespace FundingPlatform.Infrastructure.Configuration;

public enum LocalEnvironmentLoadResult
{
    Loaded,
    SkippedForEnvironment,
    SolutionRootNotFound,
    FileNotFound
}

public static class LocalEnvironmentLoader
{
    private static readonly string[] EnvironmentKeys =
    [
        "ASPNETCORE_ENVIRONMENT",
        "DOTNET_ENVIRONMENT",
        "AZURE_FUNCTIONS_ENVIRONMENT"
    ];

    public static LocalEnvironmentLoadResult TryLoad(string? startDirectory = null)
    {
        var externalEnvironments = EnvironmentKeys
            .Select(Environment.GetEnvironmentVariable)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToArray();

        if (externalEnvironments.Any(value =>
                !string.Equals(value, "Development", StringComparison.OrdinalIgnoreCase)))
        {
            return LocalEnvironmentLoadResult.SkippedForEnvironment;
        }

        var solutionRoot = FindSolutionRoot(startDirectory ?? Directory.GetCurrentDirectory());
        if (solutionRoot is null)
        {
            return LocalEnvironmentLoadResult.SolutionRootNotFound;
        }

        var environmentFile = Path.Combine(solutionRoot, ".env");
        if (!File.Exists(environmentFile))
        {
            return LocalEnvironmentLoadResult.FileNotFound;
        }

        Env.NoClobber().Load(environmentFile);
        return LocalEnvironmentLoadResult.Loaded;
    }

    private static string? FindSolutionRoot(string startDirectory)
    {
        var current = new DirectoryInfo(Path.GetFullPath(startDirectory));

        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, "FundingPlatform.sln")))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return null;
    }
}
