using Docaya.Domain.Common;

namespace Docaya.Domain.Workflow;

/// <summary>
/// Working-day arithmetic for the service-level engine.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 8.3:
/// "Weekends and client-supplied UAE public holidays are excluded. The calendar is
/// versioned reference data in <c>ref.HolidayCalendar</c>."
/// </para>
/// <para>
/// This type is pure domain logic. It takes the holiday set as data so the calendar
/// can be versioned and supplied by the Infrastructure layer without the Domain
/// depending on any store.
/// </para>
/// </remarks>
public sealed class WorkingDayCalendar
{
    /// <summary>The UAE working week runs Monday to Friday; Saturday and Sunday are the weekend.</summary>
    private static readonly IReadOnlySet<DayOfWeek> DefaultWeekend =
        new HashSet<DayOfWeek> { DayOfWeek.Saturday, DayOfWeek.Sunday };

    private readonly HashSet<DateOnly> _holidays;
    private readonly HashSet<DayOfWeek> _weekend;

    /// <summary>
    /// Creates a calendar.
    /// </summary>
    /// <param name="holidays">
    /// Public holidays to exclude. Supplied as versioned reference data from
    /// <c>ref.HolidayCalendar</c>.
    /// </param>
    /// <param name="weekend">
    /// Weekend days to exclude. Defaults to Saturday and Sunday.
    /// </param>
    /// <param name="calendarVersion">
    /// Version of the reference calendar used, so a recomputation can be attributed
    /// to a specific calendar revision.
    /// </param>
    public WorkingDayCalendar(
        IEnumerable<DateOnly>? holidays = null,
        IEnumerable<DayOfWeek>? weekend = null,
        string calendarVersion = "unversioned")
    {
        _holidays = holidays is null ? [] : [.. holidays];
        _weekend = weekend is null ? [.. DefaultWeekend] : [.. weekend];
        CalendarVersion = calendarVersion;

        if (_weekend.Count >= 7)
        {
            throw new DomainException(
                "calendar.weekend.invalid",
                "A calendar must contain at least one working day each week.");
        }
    }

    /// <summary>Version of the reference calendar this instance represents.</summary>
    public string CalendarVersion { get; }

    /// <summary>
    /// Indicates whether a date is a working day.
    /// </summary>
    /// <param name="date">The date to test.</param>
    /// <returns><c>true</c> when the date is neither a weekend day nor a public holiday.</returns>
    public bool IsWorkingDay(DateOnly date) =>
        !_weekend.Contains(date.DayOfWeek) && !_holidays.Contains(date);

    /// <summary>
    /// Advances a number of working days from a start date.
    /// </summary>
    /// <param name="start">The date to count from. It is not itself counted.</param>
    /// <param name="workingDays">The number of working days to advance. Must not be negative.</param>
    /// <returns>The date reached after advancing <paramref name="workingDays"/> working days.</returns>
    /// <exception cref="DomainException"><paramref name="workingDays"/> is negative.</exception>
    public DateOnly AddWorkingDays(DateOnly start, int workingDays)
    {
        if (workingDays < 0)
        {
            throw new DomainException(
                "calendar.workingDays.negative",
                "Working days to add must not be negative.");
        }

        var current = start;
        var remaining = workingDays;

        while (remaining > 0)
        {
            current = current.AddDays(1);
            if (IsWorkingDay(current))
            {
                remaining--;
            }
        }

        return current;
    }

    /// <summary>
    /// Counts the working days strictly after <paramref name="from"/> up to and
    /// including <paramref name="to"/>.
    /// </summary>
    /// <param name="from">The date to count from, exclusive.</param>
    /// <param name="to">The date to count to, inclusive.</param>
    /// <returns>
    /// A positive count when <paramref name="to"/> is later than <paramref name="from"/>,
    /// zero when they are equal, and a negative count when <paramref name="to"/> is earlier.
    /// </returns>
    public int CountWorkingDays(DateOnly from, DateOnly to)
    {
        if (from == to)
        {
            return 0;
        }

        var forward = to > from;
        var start = forward ? from : to;
        var end = forward ? to : from;

        var count = 0;
        for (var date = start.AddDays(1); date <= end; date = date.AddDays(1))
        {
            if (IsWorkingDay(date))
            {
                count++;
            }
        }

        return forward ? count : -count;
    }

    /// <summary>
    /// Returns the remaining working days from today to the current target.
    /// </summary>
    /// <param name="today">The date to measure from.</param>
    /// <param name="targetDate">The current service-level target date.</param>
    /// <returns>
    /// Remaining working days. Zero on the target date itself, and negative once the
    /// target has passed.
    /// </returns>
    /// <remarks>
    /// Recomputed on each calendar or target change (Technical Architecture Document
    /// v1.3, Section 8.3).
    /// </remarks>
    public int RemainingWorkingDays(DateOnly today, DateOnly targetDate) =>
        CountWorkingDays(today, targetDate);

    /// <summary>
    /// Evaluates the service-level state of an in-flight request.
    /// </summary>
    /// <param name="today">The date to evaluate on.</param>
    /// <param name="targetDate">The current target date.</param>
    /// <param name="warningWindowWorkingDays">
    /// The configured warning window. At risk is raised when the remaining days fall
    /// inside this window - before the target date, not after it.
    /// </param>
    /// <returns>The evaluated service-level state.</returns>
    /// <exception cref="DomainException">The warning window is negative.</exception>
    public SlaState EvaluateState(DateOnly today, DateOnly targetDate, int warningWindowWorkingDays)
    {
        if (warningWindowWorkingDays < 0)
        {
            throw new DomainException(
                "calendar.warningWindow.negative",
                "The warning window must not be negative.");
        }

        var remaining = RemainingWorkingDays(today, targetDate);

        if (remaining < 0)
        {
            return SlaState.Overdue;
        }

        return remaining <= warningWindowWorkingDays ? SlaState.AtRisk : SlaState.OnTrack;
    }
}
