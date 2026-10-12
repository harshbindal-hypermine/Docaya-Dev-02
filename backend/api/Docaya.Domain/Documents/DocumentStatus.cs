namespace Docaya.Domain.Documents;

/// <summary>
/// The lifecycle states a document may occupy.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 7.2 - Status State Machine.
/// Any transition not defined by <see cref="DocumentStateMachine"/> is rejected
/// by the domain and logged.
/// </remarks>
public enum DocumentStatus
{
    /// <summary>Uploaded; technical attributes populated; registration fields being completed. Staging.</summary>
    PendingRegistration = 0,

    /// <summary>Class, sensitivity, department, Standard, tags and approval flow selected and validated. Staging.</summary>
    Classified = 1,

    /// <summary>Submitted; awaiting the decision of the current review stage. Staging.</summary>
    PendingApproval = 2,

    /// <summary>A stage is actively assigned and the SLA clock is attributing time to it. Staging.</summary>
    InReview = 3,

    /// <summary>Returned with a mandatory comment to the Editor or the immediately preceding stage. Staging.</summary>
    Returned = 4,

    /// <summary>Final configured sign-off complete; promotion pending. Staging, transient.</summary>
    Approved = 5,

    /// <summary>Promoted to the SharePoint library; native version assigned.</summary>
    Published = 6,

    /// <summary>Replaced by a newer approved version created through M14.</summary>
    Superseded = 7,

    /// <summary>Within the configured expiry notification window.</summary>
    Expiring = 8,

    /// <summary>Retention reached; archived to cold tier.</summary>
    Archived = 9,

    /// <summary>Defensibly deleted with approval.</summary>
    Disposed = 10,
}
