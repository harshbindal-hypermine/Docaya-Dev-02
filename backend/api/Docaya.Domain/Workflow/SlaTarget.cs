using Docaya.Domain.Common;
using Docaya.Domain.Documents;

namespace Docaya.Domain.Workflow;

/// <summary>
/// The service-level target for an approval request.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 8.3. The original target is never
/// overwritten: both the original and the current target persist so that extension
/// behaviour is reportable.
/// </para>
/// <para>
/// Only Assurance or Authoriser may extend, and a reason is mandatory. Those
/// authority checks live in the Application layer; this type enforces the invariants
/// that hold regardless of who is asking.
/// </para>
/// </remarks>
public sealed class SlaTarget
{
    /// <summary>Default end-to-end target for <see cref="Priority.Urgent"/>, in working days.</summary>
    public const int DefaultUrgentWorkingDays = 12;

    /// <summary>Default end-to-end target for <see cref="Priority.Normal"/>, in working days.</summary>
    public const int DefaultNormalWorkingDays = 30;

    private SlaTarget(DateOnly originalTargetDate, DateOnly currentTargetDate, int targetWorkingDays)
    {
        OriginalTargetDate = originalTargetDate;
        CurrentTargetDate = currentTargetDate;
        TargetWorkingDays = targetWorkingDays;
    }

    /// <summary>The target set when the document was submitted. Never overwritten.</summary>
    public DateOnly OriginalTargetDate { get; }

    /// <summary>The target currently in force, which an authorised extension may move.</summary>
    public DateOnly CurrentTargetDate { get; private set; }

    /// <summary>The configured end-to-end target, in working days.</summary>
    public int TargetWorkingDays { get; }

    /// <summary>Whether the target has been extended at least once.</summary>
    public bool IsExtended => CurrentTargetDate != OriginalTargetDate;

    /// <summary>
    /// Returns the default end-to-end target in working days for a priority.
    /// </summary>
    /// <param name="priority">The request priority.</param>
    /// <returns>12 working days for Urgent, 30 for Normal.</returns>
    public static int DefaultWorkingDaysFor(Priority priority) => priority switch
    {
        Priority.Urgent => DefaultUrgentWorkingDays,
        _ => DefaultNormalWorkingDays,
    };

    /// <summary>
    /// Starts the service-level clock when a document is submitted.
    /// </summary>
    /// <param name="calendar">The working-day calendar in force.</param>
    /// <param name="submittedOn">The date of submission.</param>
    /// <param name="targetWorkingDays">
    /// The configured end-to-end target in working days. Use
    /// <see cref="DefaultWorkingDaysFor(Priority)"/> when the document type does not
    /// override it.
    /// </param>
    /// <returns>The started target.</returns>
    /// <exception cref="DomainException">The target is not a positive number of working days.</exception>
    public static SlaTarget Start(WorkingDayCalendar calendar, DateOnly submittedOn, int targetWorkingDays)
    {
        ArgumentNullException.ThrowIfNull(calendar);

        if (targetWorkingDays <= 0)
        {
            throw new DomainException(
                "sla.target.nonPositive",
                "A service-level target must be a positive number of working days.");
        }

        var target = calendar.AddWorkingDays(submittedOn, targetWorkingDays);
        return new SlaTarget(target, target, targetWorkingDays);
    }

    /// <summary>
    /// Records an authorised extension.
    /// </summary>
    /// <param name="newTargetDate">The revised target date. Must be later than the current target.</param>
    /// <param name="reason">Mandatory justification, recorded for reporting.</param>
    /// <exception cref="DomainException">
    /// The reason is missing, or the new target is not later than the current target.
    /// </exception>
    public void Extend(DateOnly newTargetDate, string reason)
    {
        if (string.IsNullOrWhiteSpace(reason))
        {
            throw new DomainException(
                "sla.extension.reasonRequired",
                "A reason is mandatory when extending a service-level target.");
        }

        if (newTargetDate <= CurrentTargetDate)
        {
            throw new DomainException(
                "sla.extension.notLater",
                "An extension must move the target later than the current target.");
        }

        CurrentTargetDate = newTargetDate;
    }
}
