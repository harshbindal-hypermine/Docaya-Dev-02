using Docaya.Application;
using Docaya.Infrastructure;

using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

// -----------------------------------------------------------------------------
// Docaya Functions host.
//
// Technical Architecture Document v1.3, Section 6.1: workers invoke application use
// cases and never duplicate domain logic. Section 8.5: Durable Functions hold
// orchestration state, so a worker restart resumes the orchestration rather than
// replaying side effects that have already committed.
//
// This host carries no HTTP trigger. Its surface is Durable orchestrations, Service
// Bus consumers and timer triggers; the HTTP surface belongs to src/api.
// -----------------------------------------------------------------------------

var builder = FunctionsApplication.CreateBuilder(args);

builder.Services.AddDocayaApplication();
builder.Services.AddDocayaInfrastructure(builder.Configuration);

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

await builder.Build().RunAsync();
