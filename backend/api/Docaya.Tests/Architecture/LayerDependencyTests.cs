namespace Docaya.Tests.Architecture;

/// <summary>
/// Enforces the project dependency boundaries.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 17.2 - Project Dependency Boundaries.
/// These assertions are the mechanical expression of that table.
/// </remarks>
public class LayerDependencyTests
{
    /// <summary>Provider SDK prefixes that may appear only in Infrastructure.</summary>
    private static readonly string[] ProviderPrefixes =
    [
        "Azure.",
        "Microsoft.Azure.",
        "Microsoft.Graph",
        "Microsoft.EntityFrameworkCore",
        "Microsoft.Data.SqlClient",
        "Npgsql",
        "StackExchange.Redis",
    ];

    /// <summary>
    /// The Application layer defines ports; it does not implement them, so it carries
    /// no provider SDK.
    /// </summary>
    [Fact]
    public void Application_references_no_provider_sdk()
    {
        var packages = ProjectFiles.PackageReferences("Docaya.Application");

        var offenders = packages
            .Where(package => ProviderPrefixes.Any(
                prefix => package.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            .ToList();

        Assert.True(
            offenders.Count == 0,
            "Docaya.Application defines ports and must never reference a provider SDK, but declares: "
                + string.Join(", ", offenders));
    }

    /// <summary>
    /// The Application layer sits directly on the Domain and nothing else.
    /// </summary>
    [Fact]
    public void Application_references_only_the_domain()
    {
        var projects = ProjectFiles.ProjectReferences("Docaya.Application");

        Assert.Equal(["Docaya.Domain"], projects);
    }

    /// <summary>
    /// Infrastructure implements Application ports and must not depend on the host.
    /// </summary>
    [Fact]
    public void Infrastructure_does_not_reference_the_api_host()
    {
        var projects = ProjectFiles.ProjectReferences("Docaya.Infrastructure");

        Assert.DoesNotContain("Docaya.Api", projects);
    }

    /// <summary>
    /// Infrastructure reaches the Domain through the Application, not directly.
    /// </summary>
    [Fact]
    public void Infrastructure_references_the_application()
    {
        var projects = ProjectFiles.ProjectReferences("Docaya.Infrastructure");

        Assert.Contains("Docaya.Application", projects);
    }

    /// <summary>
    /// The host composes Application and Infrastructure.
    /// </summary>
    [Fact]
    public void Api_references_application_and_infrastructure()
    {
        var projects = ProjectFiles.ProjectReferences("Docaya.Api");

        Assert.Contains("Docaya.Application", projects);
        Assert.Contains("Docaya.Infrastructure", projects);
    }
}
