using Docaya.Application.Ports;
using Docaya.Domain.Workflow;

namespace Docaya.Infrastructure.Adapters;

/// <summary>
/// Supplies the working-day calendar from reference data.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 8.3: the calendar is versioned
/// reference data in <c>ref.HolidayCalendar</c>.
/// </para>
/// <para>
/// This adapter currently returns a weekend-only calendar. It is replaced by a
/// query against <c>ref.HolidayCalendar</c> once the client supplies the UAE public
/// holiday set, at which point the calendar version flows through to every
/// recomputation.
/// </para>
/// </remarks>
public sealed class ReferenceHolidayCalendarProvider : IHolidayCalendarProvider
{
    private readonly WorkingDayCalendar _calendar;

    /// <summary>
    /// Creates the provider.
    /// </summary>
    /// <param name="holidays">Public holidays in force.</param>
    /// <param name="calendarVersion">Version of the reference calendar.</param>
    public ReferenceHolidayCalendarProvider(
        IEnumerable<DateOnly>? holidays = null,
        string calendarVersion = "weekend-only")
    {
        _calendar = new WorkingDayCalendar(holidays, weekend: null, calendarVersion);
    }

    /// <inheritdoc />
    public Task<WorkingDayCalendar> GetCurrentAsync(CancellationToken cancellationToken) =>
        Task.FromResult(_calendar);
}
