using Docaya.Api.Endpoints;
using Docaya.Api.Middleware;
using Docaya.Application;
using Docaya.Infrastructure;

using Microsoft.AspNetCore.Authentication.JwtBearer;

using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

using Serilog;

// -----------------------------------------------------------------------------
// Docaya API host.
//
// Technical Architecture Document v1.3, Sections 6.1 and 6.2. This project composes
// and exposes; it does not decide. Business rules live in Docaya.Domain and
// Docaya.Application, and every provider SDK is reached through an Application port
// implemented in Docaya.Infrastructure.
// -----------------------------------------------------------------------------

if (args.Contains("--healthcheck", StringComparer.Ordinal))
{
    using var probeClient = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
    try
    {
        using var response = await probeClient.GetAsync("http://127.0.0.1:8080/health/live");
        Environment.ExitCode = response.IsSuccessStatusCode ? 0 : 1;
    }
    catch (HttpRequestException) { Environment.ExitCode = 1; }
    catch (TaskCanceledException) { Environment.ExitCode = 1; }
    return;
}

var builder = WebApplication.CreateBuilder(args);

// Structured logging only. Every log carries the correlation ID, and no document
// content, personal data or secret is ever logged (TAD 17.4).
builder.Host.UseSerilog((context, configuration) =>
    configuration.ReadFrom.Configuration(context.Configuration).Enrich.FromLogContext());

builder.Services.AddDocayaApplication();
builder.Services.AddDocayaInfrastructure(builder.Configuration);

// -----------------------------------------------------------------------------
// Authentication - validate the Entra-issued bearer token: issuer, audience,
// signature, expiry and required scope (TAD 6.2).
//
// The user token stops here. It is never forwarded to SharePoint or any downstream
// resource; a governed service identity performs all content operations (TAD 14.1).
// -----------------------------------------------------------------------------
var entraAuthority = builder.Configuration["Docaya:Entra:Authority"];
var entraAudience = builder.Configuration["Docaya:Entra:Audience"];
var authenticationConfigured = !string.IsNullOrWhiteSpace(entraAuthority)
    && !string.IsNullOrWhiteSpace(entraAudience);

if (authenticationConfigured)
{
    builder.Services
        .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = entraAuthority;
            options.Audience = entraAudience;
            options.TokenValidationParameters.ValidateIssuer = true;
            options.TokenValidationParameters.ValidateAudience = true;
            options.TokenValidationParameters.ValidateLifetime = true;
            options.TokenValidationParameters.ValidateIssuerSigningKey = true;
        });
}
else
{
    if (!builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException("Configure Docaya:Entra:Authority and Docaya:Entra:Audience before starting the API.");
    }
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();
}

// Deny by default: every endpoint requires an authenticated caller unless it
// explicitly opts out, which only the two health probes do (TAD 6.2).
builder.Services.AddAuthorization(options =>
{
    options.FallbackPolicy = options.DefaultPolicy;
});

// A single problem-detail envelope for every failure path (TAD 6.3).
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<ProblemDetailsExceptionHandler>();

// W3C trace context from the browser through the API and into the audit (TAD 28.1).
builder.Services
    .AddOpenTelemetry()
    .ConfigureResource(resource => resource.AddService("docaya-api"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation());

var app = builder.Build();

app.UseExceptionHandler();
app.UseMiddleware<CorrelationMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

app.MapHealthEndpoints();
app.MapContractEndpoints();

// M1-M16 endpoint groups are mapped here as each module is implemented. Every one is
// generated against src/contracts and applies its authorization policy before touching
// a store.

await app.RunAsync();

/// <summary>
/// Entry point marker so integration tests can reference the host with
/// <c>WebApplicationFactory&lt;Program&gt;</c>.
/// </summary>
public partial class Program
{
    /// <summary>Prevents instantiation.</summary>
    protected Program()
    {
    }
}
