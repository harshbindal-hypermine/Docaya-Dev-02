using Docaya.Domain.Common;
using Docaya.Domain.Workflow;

namespace Docaya.Tests.Domain;

/// <summary>
/// Verifies working-day arithmetic for the service-level engine.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.3. Weekends and client-supplied UAE
/// public holidays are excluded, and "at risk" is raised before the target date, never
/// after it.
/// </remarks>
public class WorkingDayCalendarTests
{
    // Monday 5 January 2026 through Sunday 11 January 2026.
    private static readonly DateOnly Monday = new(2026, 1, 5);
    private static readonly DateOnly Friday = new(2026, 1, 9);
    private static readonly DateOnly Saturday = new(2026, 1, 10);
    private static readonly DateOnly Sunday = new(2026, 1, 11);

    [Fact]
    public void Weekdays_are_working_days()
    {
        var calendar = new WorkingDayCalendar();

        Assert.True(calendar.IsWorkingDay(Monday));
        Assert.True(calendar.IsWorkingDay(Friday));
    }

    [Fact]
    public void Weekend_days_are_not_working_days()
    {
        var calendar = new WorkingDayCalendar();

        Assert.False(calendar.IsWorkingDay(Saturday));
        Assert.False(calendar.IsWorkingDay(Sunday));
    }

    [Fact]
    public void Public_holidays_are_excluded()
    {
        var nationalDay = new DateOnly(2026, 12, 2);
        var calendar = new WorkingDayCalendar([nationalDay], calendarVersion: "uae-2026");

        Assert.False(calendar.IsWorkingDay(nationalDay));
        Assert.Equal("uae-2026", calendar.CalendarVersion);
    }

    [Fact]
    public void Adding_working_days_skips_the_weekend()
    {
        var calendar = new WorkingDayCalendar();

        // Monday + 5 working days lands on the following Monday, not Saturday.
        var result = calendar.AddWorkingDays(Monday, 5);

        Assert.Equal(new DateOnly(2026, 1, 12), result);
        Assert.Equal(DayOfWeek.Monday, result.DayOfWeek);
    }

    [Fact]
    public void Adding_working_days_skips_public_holidays()
    {
        // Wednesday 7 January 2026 is treated as a holiday.
        var holiday = new DateOnly(2026, 1, 7);
        var calendar = new WorkingDayCalendar([holiday]);

        // Monday + 3 working days: Tue, Thu, Fri - Wednesday is skipped.
        var result = calendar.AddWorkingDays(Monday, 3);

        Assert.Equal(Friday, result);
    }

    [Fact]
    public void Adding_zero_working_days_returns_the_start_date()
    {
        var calendar = new WorkingDayCalendar();

        Assert.Equal(Monday, calendar.AddWorkingDays(Monday, 0));
    }

    [Fact]
    public void Adding_negative_working_days_is_rejected()
    {
        var calendar = new WorkingDayCalendar();

        var exception = Assert.Throws<DomainException>(() => calendar.AddWorkingDays(Monday, -1));

        Assert.Equal("calendar.workingDays.negative", exception.Code);
    }

    [Fact]
    public void Counting_working_days_excludes_the_weekend()
    {
        var calendar = new WorkingDayCalendar();

        // Monday to the following Monday is five working days.
        Assert.Equal(5, calendar.CountWorkingDays(Monday, new DateOnly(2026, 1, 12)));
    }

    [Fact]
    public void Counting_the_same_day_is_zero()
    {
        var calendar = new WorkingDayCalendar();

        Assert.Equal(0, calendar.CountWorkingDays(Monday, Monday));
    }

    [Fact]
    public void Counting_backwards_is_negative()
    {
        var calendar = new WorkingDayCalendar();

        Assert.Equal(-4, calendar.CountWorkingDays(Friday, Monday));
    }

    [Fact]
    public void Add_and_count_are_inverse_operations()
    {
        var calendar = new WorkingDayCalendar([new DateOnly(2026, 1, 7)]);

        for (var days = 1; days <= 30; days++)
        {
            var target = calendar.AddWorkingDays(Monday, days);
            Assert.Equal(days, calendar.CountWorkingDays(Monday, target));
        }
    }

    [Fact]
    public void State_is_on_track_outside_the_warning_window()
    {
        var calendar = new WorkingDayCalendar();
        var target = calendar.AddWorkingDays(Monday, 10);

        Assert.Equal(SlaState.OnTrack, calendar.EvaluateState(Monday, target, warningWindowWorkingDays: 3));
    }

    [Fact]
    public void State_is_at_risk_inside_the_warning_window_before_the_target()
    {
        var calendar = new WorkingDayCalendar();
        var target = calendar.AddWorkingDays(Monday, 3);

        var state = calendar.EvaluateState(Monday, target, warningWindowWorkingDays: 3);

        // Raised before the target date, not after it.
        Assert.Equal(SlaState.AtRisk, state);
        Assert.True(calendar.RemainingWorkingDays(Monday, target) > 0);
    }

    [Fact]
    public void State_is_at_risk_on_the_target_date_itself()
    {
        var calendar = new WorkingDayCalendar();

        Assert.Equal(SlaState.AtRisk, calendar.EvaluateState(Monday, Monday, warningWindowWorkingDays: 0));
    }

    [Fact]
    public void State_is_overdue_once_the_target_has_passed()
    {
        var calendar = new WorkingDayCalendar();
        var target = calendar.AddWorkingDays(Monday, 2);
        var afterTarget = calendar.AddWorkingDays(target, 1);

        Assert.Equal(SlaState.Overdue, calendar.EvaluateState(afterTarget, target, warningWindowWorkingDays: 3));
    }

    [Fact]
    public void A_negative_warning_window_is_rejected()
    {
        var calendar = new WorkingDayCalendar();

        var exception = Assert.Throws<DomainException>(
            () => calendar.EvaluateState(Monday, Friday, warningWindowWorkingDays: -1));

        Assert.Equal("calendar.warningWindow.negative", exception.Code);
    }

    [Fact]
    public void A_calendar_with_no_working_day_is_rejected()
    {
        var everyDay = Enum.GetValues<DayOfWeek>();

        var exception = Assert.Throws<DomainException>(
            () => new WorkingDayCalendar(holidays: null, weekend: everyDay));

        Assert.Equal("calendar.weekend.invalid", exception.Code);
    }
}
