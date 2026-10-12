using Docaya.Domain.Documents;

namespace Docaya.Tests.Architecture;

/// <summary>
/// Enforces the non-negotiable dependency rule on the Domain layer.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 17.3:
/// "Add the architecture test that fails the build if Docaya.Domain references a
/// provider package."
/// </para>
/// <para>
/// Section 6.1 states the rule this test protects: "Docaya.Domain must compile with no
/// reference to any Azure, Microsoft Graph, SharePoint, EF Core or messaging package.
/// ... This is what makes the on-premises variant possible without rewriting business
/// logic, and it is enforced by an architecture test in the CI pipeline."
/// </para>
/// </remarks>
public class DomainPurityTests
{
    private const string DomainProject = "Docaya.Domain";

    /// <summary>Assembly prefixes that must never appear in the Domain.</summary>
    private static readonly string[] ForbiddenPrefixes =
    [
        "Azure.",
        "Microsoft.Azure.",
        "Microsoft.Graph",
        "Microsoft.EntityFrameworkCore",
        "Microsoft.AspNetCore",
        "Microsoft.Data.SqlClient",
        "Microsoft.Identity",
        "MediatR",
        "FluentValidation",
        "Serilog",
        "OpenTelemetry",
        "Npgsql",
        "StackExchange.Redis",
    ];

    /// <summary>
    /// The Domain project declares no NuGet package at all.
    /// </summary>
    [Fact]
    public void Domain_declares_no_package_references()
    {
        var packages = ProjectFiles.PackageReferences(DomainProject);

        Assert.True(
            packages.Count == 0,
            $"{DomainProject} must reference nothing outside the .NET base library, but declares: "
                + string.Join(", ", packages));
    }

    /// <summary>
    /// The Domain project declares no project reference either - it is the innermost layer.
    /// </summary>
    [Fact]
    public void Domain_declares_no_project_references()
    {
        var projects = ProjectFiles.ProjectReferences(DomainProject);

        Assert.True(
            projects.Count == 0,
            $"{DomainProject} is the innermost layer and must reference no other project, but declares: "
                + string.Join(", ", projects));
    }

    /// <summary>
    /// The compiled Domain assembly binds only to the .NET base library.
    /// </summary>
    [Fact]
    public void Domain_assembly_binds_only_to_the_base_library()
    {
        var domainAssembly = typeof(DocumentStatus).Assembly;
        var referenced = ProjectFiles.ReferencedAssemblies(domainAssembly);

        var offenders = referenced
            .Where(name => !name.StartsWith("System", StringComparison.Ordinal)
                && !name.Equals("netstandard", StringComparison.Ordinal)
                && !name.Equals("mscorlib", StringComparison.Ordinal))
            .ToList();

        Assert.True(
            offenders.Count == 0,
            $"{DomainProject} must bind only to the .NET base library, but references: "
                + string.Join(", ", offenders));
    }

    /// <summary>
    /// No forbidden provider assembly appears anywhere in the Domain's reference closure.
    /// </summary>
    [Fact]
    public void Domain_references_no_provider_assembly()
    {
        var domainAssembly = typeof(DocumentStatus).Assembly;
        var referenced = ProjectFiles.ReferencedAssemblies(domainAssembly);

        foreach (var prefix in ForbiddenPrefixes)
        {
            var offender = referenced.FirstOrDefault(
                name => name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));

            Assert.True(
                offender is null,
                $"{DomainProject} must never reference a provider package, but references '{offender}' "
                    + $"which matches the forbidden prefix '{prefix}'.");
        }
    }
}
