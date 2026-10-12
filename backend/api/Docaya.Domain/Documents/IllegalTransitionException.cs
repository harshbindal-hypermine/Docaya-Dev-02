using Docaya.Domain.Common;

namespace Docaya.Domain.Documents;

/// <summary>
/// Raised when a document state transition is not permitted by the state machine.
/// </summary>
public sealed class IllegalTransitionException : DomainException
{
    /// <summary>Creates an illegal transition exception.</summary>
    /// <param name="from">The state the document is currently in.</param>
    /// <param name="to">The state the caller attempted to move to.</param>
    public IllegalTransitionException(DocumentStatus from, DocumentStatus to)
        : base("document.transition.illegal", $"A document cannot move from {from} to {to}.")
    {
        From = from;
        To = to;
    }

    /// <summary>The state the document is currently in.</summary>
    public DocumentStatus From { get; }

    /// <summary>The state the caller attempted to move to.</summary>
    public DocumentStatus To { get; }
}
