using Docaya.Application.Ports;
using Docaya.Domain.Workflow;
using Docaya.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;

namespace Docaya.Infrastructure.Adapters;

/// <summary>Loads the explicitly selected calendar version from reference data.</summary>
public sealed class SqlHolidayCalendarProvider(DocayaDbContext database, IConfiguration configuration) : IHolidayCalendarProvider
{
    /// <inheritdoc />
    public async Task<WorkingDayCalendar> GetCurrentAsync(CancellationToken cancellationToken)
    {
        var code = configuration["Docaya:Calendar:Code"] ?? "UAE-FED";
        var version = configuration.GetValue("Docaya:Calendar:Version", 1);
        var week = await database.Database.SqlQuery<CalendarDay>($"SELECT DayOfWeekNo, IsWorkingDay FROM ref.WorkingWeek WHERE CalendarCode = {code} AND VersionNo = {version}")
            .ToListAsync(cancellationToken);
        if (week.Count != 7 || week.Select(day => day.DayOfWeekNo).Distinct().Count() != 7)
        {
            throw new InvalidOperationException("The configured working-week version is missing or incomplete.");
        }
        var holidays = await database.Database.SqlQuery<DateOnly>($"SELECT HolidayDate AS Value FROM ref.HolidayCalendar WHERE CalendarCode = {code} AND VersionNo = {version}")
            .ToListAsync(cancellationToken);
        var weekend = week.Where(day => !day.IsWorkingDay).Select(day => (DayOfWeek)(day.DayOfWeekNo % 7));
        return new WorkingDayCalendar(holidays, weekend, $"{code}:{version}");
    }
}

/// <summary>A row of the configured ISO working week.</summary>
public sealed class CalendarDay
{
    public byte DayOfWeekNo { get; set; }
    public bool IsWorkingDay { get; set; }
}
