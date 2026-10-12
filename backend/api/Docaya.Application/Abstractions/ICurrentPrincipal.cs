namespace Docaya.Application.Abstractions;

/// <summary>
/// Identifies the caller of the current request.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 14.3. Claims are sourced from the
/// Entra-issued token. The token itself never leaves the API.
/// </remarks>
public interface ICurrentPrincipal
{
    /// <summary>The caller's object identifier.</summary>
    Guid PrincipalId { get; }

    /// <summary>The caller's display name, used for timeline and audit attribution.</summary>
    string DisplayName { get; }

    /// <summary>The caller's assigned roles.</summary>
    IReadOnlyCollection<string> Roles { get; }

    /// <summary>The departments the caller is scoped to.</summary>
    IReadOnlyCollection<Guid> DepartmentIds { get; }

    /// <summary>Whether a caller is authenticated at all.</summary>
    bool IsAuthenticated { get; }
}
