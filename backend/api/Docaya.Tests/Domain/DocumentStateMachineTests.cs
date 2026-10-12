using Docaya.Domain.Common;
using Docaya.Domain.Documents;

namespace Docaya.Tests.Domain;

/// <summary>
/// Verifies the document state machine.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 7.2 and Section 17.7:
/// "Transitions are checked against Figure 5; an illegal transition must fail a unit test."
/// </remarks>
public class DocumentStateMachineTests
{
    [Theory]
    [InlineData(DocumentStatus.PendingRegistration, DocumentStatus.Classified)]
    [InlineData(DocumentStatus.Classified, DocumentStatus.PendingApproval)]
    [InlineData(DocumentStatus.PendingApproval, DocumentStatus.InReview)]
    [InlineData(DocumentStatus.InReview, DocumentStatus.PendingApproval)]
    [InlineData(DocumentStatus.InReview, DocumentStatus.Returned)]
    [InlineData(DocumentStatus.InReview, DocumentStatus.Approved)]
    [InlineData(DocumentStatus.Returned, DocumentStatus.PendingApproval)]
    [InlineData(DocumentStatus.Approved, DocumentStatus.Published)]
    [InlineData(DocumentStatus.Published, DocumentStatus.Superseded)]
    [InlineData(DocumentStatus.Published, DocumentStatus.Expiring)]
    [InlineData(DocumentStatus.Archived, DocumentStatus.Disposed)]
    public void Permitted_transitions_are_allowed(DocumentStatus from, DocumentStatus to)
    {
        Assert.True(DocumentStateMachine.CanTransition(from, to));

        // Must not throw.
        DocumentStateMachine.EnsureCanTransition(from, to);
    }

    [Theory]
    [InlineData(DocumentStatus.PendingRegistration, DocumentStatus.Published)]
    [InlineData(DocumentStatus.PendingRegistration, DocumentStatus.Approved)]
    [InlineData(DocumentStatus.Classified, DocumentStatus.Published)]
    [InlineData(DocumentStatus.PendingApproval, DocumentStatus.Published)]
    [InlineData(DocumentStatus.PendingApproval, DocumentStatus.Approved)]
    [InlineData(DocumentStatus.InReview, DocumentStatus.Published)]
    [InlineData(DocumentStatus.Returned, DocumentStatus.Approved)]
    [InlineData(DocumentStatus.Published, DocumentStatus.PendingRegistration)]
    [InlineData(DocumentStatus.Disposed, DocumentStatus.Published)]
    [InlineData(DocumentStatus.Disposed, DocumentStatus.Archived)]
    public void Illegal_transitions_are_rejected(DocumentStatus from, DocumentStatus to)
    {
        Assert.False(DocumentStateMachine.CanTransition(from, to));

        var exception = Assert.Throws<IllegalTransitionException>(
            () => DocumentStateMachine.EnsureCanTransition(from, to));

        Assert.Equal("document.transition.illegal", exception.Code);
        Assert.Equal(from, exception.From);
        Assert.Equal(to, exception.To);
    }

    /// <summary>
    /// No staging state other than Approved can reach Published. This is the structural
    /// guarantee that nothing is published before the configured final approval stage
    /// completes. Expiring may return to Published because that content is already
    /// published - it is a renewal, not a new publication.
    /// </summary>
    [Fact]
    public void No_unapproved_staging_state_can_reach_published()
    {
        DocumentStatus[] stagingStates =
        [
            DocumentStatus.PendingRegistration,
            DocumentStatus.Classified,
            DocumentStatus.PendingApproval,
            DocumentStatus.InReview,
            DocumentStatus.Returned,
        ];

        foreach (var state in stagingStates)
        {
            Assert.False(
                DocumentStateMachine.CanTransition(state, DocumentStatus.Published),
                $"{state} must not be able to reach Published without passing through Approved.");
        }

        Assert.True(DocumentStateMachine.CanTransition(DocumentStatus.Approved, DocumentStatus.Published));
    }

    /// <summary>
    /// A document under legal hold cannot be archived or disposed regardless of its
    /// retention schedule (TAD 7.2).
    /// </summary>
    [Theory]
    [InlineData(DocumentStatus.Published, DocumentStatus.Archived)]
    [InlineData(DocumentStatus.Superseded, DocumentStatus.Archived)]
    [InlineData(DocumentStatus.Archived, DocumentStatus.Disposed)]
    public void Legal_hold_blocks_disposition(DocumentStatus from, DocumentStatus to)
    {
        // The transition itself is legal.
        Assert.True(DocumentStateMachine.CanTransition(from, to));

        var exception = Assert.Throws<DomainException>(
            () => DocumentStateMachine.EnsureCanTransition(from, to, isUnderLegalHold: true));

        Assert.Equal("document.legalHold.blocksDisposition", exception.Code);
    }

    /// <summary>
    /// Legal hold does not interfere with transitions that are not dispositions.
    /// </summary>
    [Fact]
    public void Legal_hold_does_not_block_non_disposition_transitions()
    {
        DocumentStateMachine.EnsureCanTransition(
            DocumentStatus.Published,
            DocumentStatus.Superseded,
            isUnderLegalHold: true);
    }

    /// <summary>
    /// Disposed is terminal.
    /// </summary>
    [Fact]
    public void Disposed_is_terminal()
    {
        Assert.Empty(DocumentStateMachine.AllowedFrom(DocumentStatus.Disposed));
    }
}
