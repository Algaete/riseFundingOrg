using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace FundingPlatform.IntegrationTests;

public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public ApiFactory()
    {
        Environment.SetEnvironmentVariable("ASPNETCORE_ENVIRONMENT", "Testing");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Web:FrontendBaseUrl"] = "http://localhost:5173",
                ["Web:AllowedCorsOrigins:0"] = "http://localhost:5173",
                ["Authentication:Jwt:Issuer"] = "https://testing.fundingplatform.local",
                ["Authentication:Jwt:Audience"] = "FundingPlatform.Tests",
                ["Authentication:Jwt:SigningKey"] = Convert.ToBase64String(new byte[64]),
                ["Authentication:SecurityHash:IpHashPepper"] =
                    Convert.ToBase64String(new byte[32]),
                ["Authentication:SecurityHash:RecoveryCodePepper"] =
                    Convert.ToBase64String(new byte[32]),
                ["Email:Endpoint"] = "https://testing.communication.azure.com",
                ["Email:FromAddress"] = "noreply@testing.example",
                ["Email:FrontendBaseUrl"] = "http://localhost:5173",
                ["SourceDocuments:BlobServiceUri"] = "https://testing.blob.core.windows.net",
                ["SourceDocuments:IncomingContainer"] = "fp-source-incoming",
                ["SourceDocuments:QuarantineContainer"] = "fp-source-quarantine",
                ["SourceDocuments:TrustedContainer"] = "fp-source-trusted",
                ["SourceDocuments:MaxBytes"] = "26214400",
                ["SourceDocuments:UploadTtlMinutes"] = "5",
                ["SourceDocuments:FinalizeLeaseSeconds"] = "120",
                ["SourceDocuments:ScanTimeoutSeconds"] = "10",
                ["SourceDocuments:ScanMode"] = "DevelopmentFake",
                ["SourceDocuments:DevelopmentFakeResult"] = "Clean"
            });
        });
    }
}
