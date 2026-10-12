using System.Reflection;
using System.Xml.Linq;

namespace Docaya.Tests.Architecture;

/// <summary>
/// Locates project files at test time so architecture rules can be asserted against
/// the declared dependencies, not only the compiled ones.
/// </summary>
internal static class ProjectFiles
{
    /// <summary>
    /// Returns the absolute path to <c>src/api</c>.
    /// </summary>
    /// <returns>The API package root.</returns>
    /// <exception cref="InvalidOperationException">The root could not be located.</exception>
    public static string ApiRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);

        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Docaya.Api.sln")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new InvalidOperationException(
            "Could not locate src/api by walking up from the test output directory.");
    }

    /// <summary>
    /// Loads a project file.
    /// </summary>
    /// <param name="projectName">Project name, for example <c>Docaya.Domain</c>.</param>
    /// <returns>The parsed project document.</returns>
    public static XDocument Load(string projectName)
    {
        var path = Path.Combine(ApiRoot(), projectName, $"{projectName}.csproj");

        if (!File.Exists(path))
        {
            throw new FileNotFoundException($"Project file not found: {path}", path);
        }

        return XDocument.Load(path);
    }

    /// <summary>
    /// Returns the package identifiers declared by a project.
    /// </summary>
    /// <param name="projectName">Project name.</param>
    /// <returns>The declared <c>PackageReference</c> identifiers.</returns>
    public static IReadOnlyList<string> PackageReferences(string projectName) =>
        [.. Load(projectName)
            .Descendants("PackageReference")
            .Select(element => element.Attribute("Include")?.Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value!)];

    /// <summary>
    /// Returns the project names a project references.
    /// </summary>
    /// <param name="projectName">Project name.</param>
    /// <returns>The referenced project names, without path or extension.</returns>
    public static IReadOnlyList<string> ProjectReferences(string projectName) =>
        [.. Load(projectName)
            .Descendants("ProjectReference")
            .Select(element => element.Attribute("Include")?.Value)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => Path.GetFileNameWithoutExtension(value!))];

    /// <summary>
    /// Returns the assemblies an assembly references at runtime.
    /// </summary>
    /// <param name="assembly">The assembly to inspect.</param>
    /// <returns>The referenced assembly names.</returns>
    public static IReadOnlyList<string> ReferencedAssemblies(Assembly assembly) =>
        [.. assembly.GetReferencedAssemblies().Select(name => name.Name ?? string.Empty)];
}
