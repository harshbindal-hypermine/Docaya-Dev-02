using Microsoft.Extensions.DependencyInjection;

namespace Docaya.Application;

/// <summary>
/// Registers the Application layer with the dependency injection container.
/// </summary>
public static class ApplicationServiceCollectionExtensions
{
    /// <summary>
    /// Adds use cases, validators and behaviours.
    /// </summary>
    /// <param name="services">The service collection.</param>
    /// <returns>The same service collection, for chaining.</returns>
    /// <remarks>
    /// The Application layer registers only its own types. Ports are bound to adapters
    /// by Infrastructure, which is the only layer permitted to reference a provider SDK
    /// (Technical Architecture Document v1.3, Section 17.2).
    /// </remarks>
    public static IServiceCollection AddDocayaApplication(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        // Use case handlers, validators and pipeline behaviours are registered here as
        // the M1-M16 modules are implemented.
        return services;
    }
}
