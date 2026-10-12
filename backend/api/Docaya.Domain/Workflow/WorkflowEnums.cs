namespace Docaya.Domain.Workflow;

/// <summary>
/// The decision a reviewer records at a stage.
/// </summary>
public enum ReviewDecisionType
{
    /// <summary>The stage approves and the chain advances.</summary>
    Approve = 0,

    /// <summary>The stage returns the item with a mandatory comment and correction point.</summary>
    Return = 1,
}

/// <summary>
/// Where a returned item re-enters the review chain.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.4: a return is never a restart.
/// The item re-enters the chain at the correction point, preserving the decision
/// history and the elapsed SLA.
/// </remarks>
public enum CorrectionPoint
{
    /// <summary>Return to the Editor who submitted the document.</summary>
    Editor = 0,

    /// <summary>Return to the immediately preceding stage.</summary>
    PrecedingStage = 1,
}

/// <summary>
/// The routing primitive governing how a stage is satisfied.
/// </summary>
/// <remarks>Technical Architecture Document v1.3, Section 8.2.</remarks>
public enum RoutingPattern
{
    /// <summary>Each stage must approve before the next begins.</summary>
    Sequential = 0,

    /// <summary>Several reviewers act concurrently; quorum or unanimous configured per stage.</summary>
    Parallel = 1,

    /// <summary>A rule adds or removes a stage, for example Secret adds a compliance reviewer.</summary>
    Conditional = 2,

    /// <summary>Out-of-office auto-reassignment within the same stage and role.</summary>
    Delegation = 3,
}

/// <summary>
/// The service-level state of an in-flight approval request.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.3. At risk is raised before the
/// target date, not after it. An overdue request remains actionable and continues to
/// accrue stage duration.
/// </remarks>
public enum SlaState
{
    /// <summary>Remaining working days are outside the warning window.</summary>
    OnTrack = 0,

    /// <summary>Remaining working days have fallen inside the configured warning window.</summary>
    AtRisk = 1,

    /// <summary>The current target has passed.</summary>
    Overdue = 2,
}
