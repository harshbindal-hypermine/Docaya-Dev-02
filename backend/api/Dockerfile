# =============================================================================
# Docaya API container image.
#
# Technical Architecture Document v1.3, Section 17.1: src/api produces an immutable
# container image, referenced downstream by digest and never by a floating tag.
# Section 19.3 - Release Integrity Principles.
# =============================================================================

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Central package management files first, so a dependency change - and only a
# dependency change - invalidates the restore layer.
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY src/api/Docaya.Api.sln ./src/api/
COPY src/api/Docaya.Domain/Docaya.Domain.csproj ./src/api/Docaya.Domain/
COPY src/api/Docaya.Application/Docaya.Application.csproj ./src/api/Docaya.Application/
COPY src/api/Docaya.Infrastructure/Docaya.Infrastructure.csproj ./src/api/Docaya.Infrastructure/
COPY src/api/Docaya.Api/Docaya.Api.csproj ./src/api/Docaya.Api/
COPY src/api/Docaya.Tests/Docaya.Tests.csproj ./src/api/Docaya.Tests/

RUN dotnet restore src/api/Docaya.Api.sln

COPY src/api/ ./src/api/

# The architecture test fails the build if Docaya.Domain references a provider
# package, so a violation never reaches an image (TAD 17.3).
RUN dotnet test src/api/Docaya.Api.sln --no-restore --configuration Release

RUN dotnet publish src/api/Docaya.Api/Docaya.Api.csproj \
    --no-restore \
    --configuration Release \
    --output /app/publish

# -----------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_EnableDiagnostics=0

COPY --from=build /app/publish ./

# Run as a non-root user.
USER $APP_UID

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
    CMD ["dotnet", "Docaya.Api.dll", "--healthcheck"]

ENTRYPOINT ["dotnet", "Docaya.Api.dll"]
