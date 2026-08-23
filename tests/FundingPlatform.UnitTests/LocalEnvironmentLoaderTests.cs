using FundingPlatform.Infrastructure.Configuration;

namespace FundingPlatform.UnitTests;

public sealed class LocalEnvironmentLoaderTests
{
    [Fact]
    public void Missing_external_environment_loads_dotenv()
    {
        var variableName = $"FUNDING_PLATFORM_TEST_{Guid.NewGuid():N}";
        using var environment = new EnvironmentScope(new Dictionary<string, string?>
        {
            ["ASPNETCORE_ENVIRONMENT"] = null,
            ["DOTNET_ENVIRONMENT"] = null,
            ["AZURE_FUNCTIONS_ENVIRONMENT"] = null,
            [variableName] = null
        });
        using var repository = TemporaryRepository.Create($"{variableName}=from-file");

        var result = LocalEnvironmentLoader.TryLoad(repository.NestedDirectory);

        Assert.Equal(LocalEnvironmentLoadResult.Loaded, result);
        Assert.Equal("from-file", Environment.GetEnvironmentVariable(variableName));
    }

    [Fact]
    public void Development_env_load_preserves_existing_process_values()
    {
        var variableName = $"FUNDING_PLATFORM_TEST_{Guid.NewGuid():N}";
        using var environment = new EnvironmentScope(new Dictionary<string, string?>
        {
            ["ASPNETCORE_ENVIRONMENT"] = "Development",
            ["DOTNET_ENVIRONMENT"] = null,
            ["AZURE_FUNCTIONS_ENVIRONMENT"] = null,
            [variableName] = "from-process"
        });
        using var repository = TemporaryRepository.Create($"{variableName}=from-file");

        var result = LocalEnvironmentLoader.TryLoad(repository.NestedDirectory);

        Assert.Equal(LocalEnvironmentLoadResult.Loaded, result);
        Assert.Equal("from-process", Environment.GetEnvironmentVariable(variableName));
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public void Non_development_environment_never_loads_dotenv(string environmentName)
    {
        var variableName = $"FUNDING_PLATFORM_TEST_{Guid.NewGuid():N}";
        using var environment = new EnvironmentScope(new Dictionary<string, string?>
        {
            ["ASPNETCORE_ENVIRONMENT"] = environmentName,
            ["DOTNET_ENVIRONMENT"] = null,
            ["AZURE_FUNCTIONS_ENVIRONMENT"] = null,
            [variableName] = null
        });
        using var repository = TemporaryRepository.Create($"{variableName}=from-file");

        var result = LocalEnvironmentLoader.TryLoad(repository.NestedDirectory);

        Assert.Equal(LocalEnvironmentLoadResult.SkippedForEnvironment, result);
        Assert.Null(Environment.GetEnvironmentVariable(variableName));
    }

    private sealed class EnvironmentScope : IDisposable
    {
        private readonly Dictionary<string, string?> originalValues;

        public EnvironmentScope(IReadOnlyDictionary<string, string?> values)
        {
            originalValues = values.Keys.ToDictionary(
                key => key,
                Environment.GetEnvironmentVariable);

            foreach (var (key, value) in values)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
        }

        public void Dispose()
        {
            foreach (var (key, value) in originalValues)
            {
                Environment.SetEnvironmentVariable(key, value);
            }
        }
    }

    private sealed class TemporaryRepository : IDisposable
    {
        private TemporaryRepository(string rootDirectory, string nestedDirectory)
        {
            RootDirectory = rootDirectory;
            NestedDirectory = nestedDirectory;
        }

        public string RootDirectory { get; }

        public string NestedDirectory { get; }

        public static TemporaryRepository Create(string environmentFileContents)
        {
            var root = Path.Combine(Path.GetTempPath(), $"funding-platform-{Guid.NewGuid():N}");
            var nested = Path.Combine(root, "src", "test");
            Directory.CreateDirectory(nested);
            File.WriteAllText(Path.Combine(root, "FundingPlatform.sln"), string.Empty);
            File.WriteAllText(Path.Combine(root, ".env"), environmentFileContents);
            return new TemporaryRepository(root, nested);
        }

        public void Dispose() => Directory.Delete(RootDirectory, recursive: true);
    }
}
