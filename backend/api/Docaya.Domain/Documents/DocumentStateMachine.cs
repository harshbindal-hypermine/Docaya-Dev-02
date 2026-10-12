using Docaya.Domain.Common;

namespace Docaya.Domain.Documents;

/// <summary>
/// The authoritative document state machine.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 7.2:
/// "Any transition not shown is rejected by the domain state machine and logged."
/// </para>
/// <para>
/// Two non-negotiable lifecycle controls are encoded structurally rather than by
/// convention. <see cref="DocumentStatus.Published"/> is reachable only from
/// <see cref="DocumentStatus.Approved"/>, so no document can be published before
/// the configured final approval stage completes. And a document under legal hold
/// cannot be archived or disposed regardless of its retention schedule.
/// </para>
/// </remarks>
public static class DocumentStateMachine
{
    private static readonly Dictionary<DocumentStatus, HashSet<DocumentStatus>> AllowedTransitions = new()
    {
        // Capture and registration. Classification is manual and Editor-driven.
        [DocumentStatus.PendingRegistration] =
        [
            DocumentStatus.Classified,
        ],

        // A classified draft is submitted, or reopened for further editing.
        [DocumentStatus.Classified] =
        [
            DocumentStatus.PendingRegistration,
            DocumentStatus.PendingApproval,
        ],

        // The workflow engine assigns the next configured stage.
        [DocumentStatus.PendingApproval] =
        [
            DocumentStatus.InReview,
        ],

        // A stage approves and the chain advances, approves as the final stage,
        // or returns to the selected correction point.
        [DocumentStatus.InReview] =
        [
            DocumentStatus.PendingApproval,
            DocumentStatus.Approved,
            DocumentStatus.Returned,
        ],

        // A return is never a restart: the item re-enters the chain at the
        // correction point, preserving decision history and elapsed SLA.
        [DocumentStatus.Returned] =
        [
            DocumentStatus.Classified,
            DocumentStatus.PendingApproval,
        ],

        // Approved is transient. Only the promotion worker moves it to Published.
        [DocumentStatus.Approved] =
        [
            DocumentStatus.Published,
        ],

        [DocumentStatus.Published] =
        [
            DocumentStatus.Superseded,
            DocumentStatus.Expiring,
            DocumentStatus.Archived,
        ],

        [DocumentStatus.Expiring] =
        [
            DocumentStatus.Published,
            DocumentStatus.Superseded,
            DocumentStatus.Archived,
        ],

        [DocumentStatus.Superseded] =
        [
            DocumentStatus.Archived,
        ],

        [DocumentStatus.Archived] =
        [
            DocumentStatus.Disposed,
        ],

        // Terminal.
        [DocumentStatus.Disposed] = [],
    };

    private static readonly HashSet<DocumentStatus> DispositionStates =
    [
        DocumentStatus.Archived,
        DocumentStatus.Disposed,
    ];

    /// <summary>
    /// Returns the states reachable from <paramref name="from"/>.
    /// </summary>
    /// <param name="from">The current state.</param>
    /// <returns>The permitted target states, empty for a terminal state.</returns>
    public static IReadOnlySet<DocumentStatus> AllowedFrom(DocumentStatus from) =>
        AllowedTransitions.TryGetValue(from, out var allowed) ? allowed : [];

    /// <summary>
    /// Indicates whether a transition is permitted, ignoring legal hold.
    /// </summary>
    /// <param name="from">The current state.</param>
    /// <param name="to">The proposed target state.</param>
    /// <returns><c>true</c> when the transition appears in the state machine.</returns>
    public static bool CanTransition(DocumentStatus from, DocumentStatus to) =>
        AllowedFrom(from).Contains(to);

    /// <summary>
    /// Indicates whether a state is a disposition state - archive or disposal.
    /// </summary>
    /// <param name="status">The state to test.</param>
    /// <returns><c>true</c> for <see cref="DocumentStatus.Archived"/> or <see cref="DocumentStatus.Disposed"/>.</returns>
    public static bool IsDisposition(DocumentStatus status) => DispositionStates.Contains(status);

    /// <summary>
    /// Validates a transition and throws when it is not permitted.
    /// </summary>
    /// <param name="from">The current state.</param>
    /// <param name="to">The proposed target state.</param>
    /// <param name="isUnderLegalHold">
    /// Whether the document is under legal hold. A document under legal hold cannot be
    /// archived or disposed regardless of its retention schedule (TAD 7.2).
    /// </param>
    /// <exception cref="IllegalTransitionException">The transition is not in the state machine.</exception>
    /// <exception cref="DomainException">The transition is blocked by a legal hold.</exception>
    public static void EnsureCanTransition(DocumentStatus from, DocumentStatus to, bool isUnderLegalHold = false)
    {
        if (!CanTransition(from, to))
        {
            throw new IllegalTransitionException(from, to);
        }

        if (isUnderLegalHold && IsDisposition(to))
        {
            throw new DomainException(
                "document.legalHold.blocksDisposition",
                $"A document under legal hold cannot move to {to}.");
        }
    }
}
