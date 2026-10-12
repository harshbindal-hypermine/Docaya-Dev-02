namespace Docaya.Domain.Documents;

/// <summary>
/// Sensitivity classification, selected manually by the Editor.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, reconciliation register: auto-approval for
/// Public sensitivity was deleted in v1.3. Publication always requires completion of
/// the configured final approval stage, whatever the sensitivity.
/// </remarks>
public enum Sensitivity
{
    /// <summary>Publicly releasable.</summary>
    Public = 0,

    /// <summary>Internal to the organisation.</summary>
    Internal = 1,

    /// <summary>Restricted to named departments or roles.</summary>
    Confidential = 2,

    /// <summary>Highest restriction. Conditional routing may add a compliance reviewer.</summary>
    Secret = 3,
}

/// <summary>
/// Request priority, which selects the working-day service-level target.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.3: Urgent is 12 working days
/// end-to-end and Normal is 30 working days end-to-end. Both are configurable per
/// document type.
/// </remarks>
public enum Priority
{
    /// <summary>Default target of 30 working days end-to-end.</summary>
    Normal = 0,

    /// <summary>Accelerated target of 12 working days end-to-end.</summary>
    Urgent = 1,
}

/// <summary>
/// Publishing scope, a classification dimension introduced in v1.3.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, reconciliation register: Department Tag and
/// Publishing Scope are captured at registration and drive navigation, visibility and
/// notification reach.
/// </remarks>
public enum PublishingScope
{
    /// <summary>Visible within the owning department only.</summary>
    Department = 0,

    /// <summary>Visible to named collaborating departments.</summary>
    CrossDepartment = 1,

    /// <summary>Visible across the organisation.</summary>
    Organisation = 2,
}
