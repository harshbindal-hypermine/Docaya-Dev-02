using Docaya.Application.Ports;
using Docaya.Infrastructure.Adapters;
using Docaya.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Docaya.Infrastructure;

/// <summary>
/// Binds Application ports to their concrete adapters.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 17.2. This is the only composition
/// point where provider SDKs are permitted. Swapping the Azure-native adapters for the
/// on-premises variant in Section 22 is a change here, not in the Domain or Application.
/// </remarks>
public static class InfrastructureServiceCollectionExtensions
{
    /// <summary>
    /// Adds persistence and the provider adapters.
    /// </summary>
    /// <param name="services">The service collection.</param>
    /// <param name="configuration">Host configuration.</param>
    /// <returns>The same service collection, for chaining.</returns>
    public static IServiceCollection AddDocayaInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);

        var connectionString = configuration.GetConnectionString("DocayaSql");

        if (!string.IsNullOrWhiteSpace(connectionString))
        {
            services.AddDbContext<DocayaDbContext>(options =>
                options.UseSqlServer(connectionString, sql => sql.EnableRetryOnFailure()));
            services.AddScoped<IHolidayCalendarProvider, SqlHolidayCalendarProvider>();
        }

        services.AddSingleton<IClock>(_ => new SystemClock(ResolveOperatingTimeZone(configuration)));
        services.AddScoped<IAuditWriter, AuditWriter>();
        services.AddScoped<IAuthorizationPolicyEvaluator, AuthorizationPolicyEvaluator>();
        services.AddScoped<IContentPromoter, ContentPromoter>();
        services.AddScoped<IEventPublisher, EventPublisher>();
        services.AddScoped<IIdempotencyStore, IdempotencyStore>();
        services.AddScoped<ISearchIndexPort, SearchIndexPort>();
        services.AddScoped<IStagingContentStore, StagingContentStore>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        // Blob, Graph, Search, embedding, messaging and Power BI adapters are registered
        // here as the corresponding modules are implemented. Each is bound to an
        // Application port and authenticates with a workload identity.
        return services;
    }

    private static TimeZoneInfo ResolveOperatingTimeZone(IConfiguration configuration)
    {
        var id = configuration["Docaya:OperatingTimeZone"];

        if (string.IsNullOrWhiteSpace(id))
        {
            return TimeZoneInfo.Utc;
        }

        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(id);
        }
        catch (TimeZoneNotFoundException)
        {
            return TimeZoneInfo.Utc;
        }
        catch (InvalidTimeZoneException)
        {
            return TimeZoneInfo.Utc;
        }
    }
}
