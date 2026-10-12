using Docaya.Domain.Workflow;

namespace Docaya.Application.Ports;

/// <summary>
/// Supplies the versioned working-day calendar.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.3: the calendar is versioned
/// reference data in <c>ref.HolidayCalendar</c>. This port lets the Domain perform
/// working-day arithmetic without depending on any store.
/// </remarks>
public interface IHolidayCalendarProvider
{
    /// <summary>
    /// Returns the calendar in force, including client-supplied UAE public holidays.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The working-day calendar.</returns>
    Task<WorkingDayCalendar> GetCurrentAsync(CancellationToken cancellationToken);
}
