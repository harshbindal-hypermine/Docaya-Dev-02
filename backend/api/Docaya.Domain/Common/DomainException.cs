namespace Docaya.Domain.Common;

/// <summary>
/// Raised when an operation would violate a domain invariant.
/// </summary>
/// <remarks>
/// Domain exceptions map to conflict or unprocessable responses in the API
/// pipeline (Technical Architecture Document v1.3, Section 6.2). The message is
/// safe for display: it never contains document content, personal data or secrets.
/// </remarks>
public class DomainException : Exception
{
    /// <summary>Creates a domain exception with a stable machine-readable code.</summary>
    /// <param name="code">Stable error code carried into the problem-detail envelope.</param>
    /// <param name="message">Human-readable message, safe for display.</param>
    public DomainException(string code, string message)
        : base(message)
    {
        Code = code;
    }

    /// <summary>Stable machine-readable error code, for example <c>document.transition.illegal</c>.</summary>
    public string Code { get; } = "domain.error";
}
