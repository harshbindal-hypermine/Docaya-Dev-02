using Docaya.Infrastructure.Persistence;

namespace Docaya.Api.Endpoints;

/// <summary>
/// Liveness and readiness probes.
/// </summary>
/// <remarks>
/// These are the only two operations permitted to be anonymous. The contract test in
/// <c>src/contracts</c> fails the build if any other operation declares
/// <c>security: []</c>.
/// </remarks>
public static class HealthEndpoints
{
    /// <summary>
    /// Maps the health endpoints.
    /// </summary>
    /// <param name="app">The endpoint route builder.</param>
    /// <returns>The same builder, for chaining.</returns>
    public static IEndpointRouteBuilder MapHealthEndpoints(this IEndpointRouteBuilder app)
    {
        ArgumentNullException.ThrowIfNull(app);

        var group = app.MapGroup("/health").AllowAnonymous().WithTags("Health");

        group.MapGet("/live", () => Results.Ok(new HealthStatusResponse("healthy", [])))
            .WithName("getHealthLive")
            .WithSummary("Liveness probe.");

        group.MapGet("/ready", async (IServiceProvider services, IConfiguration configuration, CancellationToken cancellationToken) =>
        {
            var database = services.GetService<DocayaDbContext>();
            var databaseReady = database is not null && await database.Database.CanConnectAsync(cancellationToken);
            var authenticationReady = !string.IsNullOrWhiteSpace(configuration["Docaya:Entra:Authority"])
                && !string.IsNullOrWhiteSpace(configuration["Docaya:Entra:Audience"]);
            var ready = databaseReady && authenticationReady;
            var status = new HealthStatusResponse(ready ? "healthy" : "unhealthy",
            [
                new("sql", databaseReady ? "healthy" : "unhealthy"),
                new("authentication", authenticationReady ? "healthy" : "unhealthy"),
            ]);
            return Results.Json(status, statusCode: ready ? StatusCodes.Status200OK : StatusCodes.Status503ServiceUnavailable);
        })
            .WithName("getHealthReady")
            .WithSummary("Readiness probe.");

        return app;
    }
}

/// <summary>
/// The health probe response.
/// </summary>
/// <param name="Status">Overall status: healthy, degraded or unhealthy.</param>
/// <param name="Checks">Per-dependency results.</param>
public sealed record HealthStatusResponse(string Status, IReadOnlyCollection<HealthCheckResult> Checks);

/// <summary>
/// The result of one dependency check.
/// </summary>
/// <param name="Name">Dependency name.</param>
/// <param name="Status">Dependency status.</param>
public sealed record HealthCheckResult(string Name, string Status);
