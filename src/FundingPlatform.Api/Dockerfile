FROM mcr.microsoft.com/dotnet/sdk:10.0.302-noble AS build
WORKDIR /source

COPY Directory.Build.props Directory.Packages.props global.json ./
COPY src/FundingPlatform.Api/FundingPlatform.Api.csproj src/FundingPlatform.Api/
COPY src/FundingPlatform.Application/FundingPlatform.Application.csproj src/FundingPlatform.Application/
COPY src/FundingPlatform.Contracts/FundingPlatform.Contracts.csproj src/FundingPlatform.Contracts/
COPY src/FundingPlatform.Core/FundingPlatform.Core.csproj src/FundingPlatform.Core/
COPY src/FundingPlatform.Infrastructure/FundingPlatform.Infrastructure.csproj src/FundingPlatform.Infrastructure/
RUN dotnet restore src/FundingPlatform.Api/FundingPlatform.Api.csproj

COPY src/ src/
RUN dotnet publish src/FundingPlatform.Api/FundingPlatform.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS runtime
WORKDIR /app
ENV ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
EXPOSE 8080
COPY --from=build --chown=$APP_UID:$APP_UID /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "FundingPlatform.Api.dll"]
