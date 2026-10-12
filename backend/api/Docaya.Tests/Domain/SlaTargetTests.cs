using Docaya.Domain.Common;
using Docaya.Domain.Documents;
using Docaya.Domain.Workflow;

namespace Docaya.Tests.Domain;

/// <summary>
/// Verifies the service-level target and its extension rules.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.3: a reason is mandatory and the
/// original target is never overwritten - both dates persist for reporting.
/// </remarks>
public class SlaTargetTests
{
    private static readonly DateOnly SubmittedOn = new(2026, 1, 5);

    [Fact]
    public void Urgent_defaults_to_twelve_working_days()
    {
        Assert.Equal(12, SlaTarget.DefaultWorkingDaysFor(Priority.Urgent));
    }

    [Fact]
    public void Normal_defaults_to_thirty_working_days()
    {
        Assert.Equal(30, SlaTarget.DefaultWorkingDaysFor(Priority.Normal));
    }

    [Fact]
    public void Starting_sets_the_original_and_current_target_to_the_same_date()
    {
        var calendar = new WorkingDayCalendar();

        var target = SlaTarget.Start(calendar, SubmittedOn, SlaTarget.DefaultWorkingDaysFor(Priority.Urgent));

        Assert.Equal(target.OriginalTargetDate, target.CurrentTargetDate);
        Assert.Equal(12, target.TargetWorkingDays);
        Assert.False(target.IsExtended);
    }

    [Fact]
    public void Starting_counts_in_working_days_not_calendar_days()
    {
        var calendar = new WorkingDayCalendar();

        var target = SlaTarget.Start(calendar, SubmittedOn, 12);

        // Twelve working days from Monday 5 January 2026 is Wednesday 21 January 2026:
        // four working days in the first week, five in the second, three in the third.
        Assert.Equal(new DateOnly(2026, 1, 21), target.CurrentTargetDate);
        Assert.Equal(DayOfWeek.Wednesday, target.CurrentTargetDate.DayOfWeek);
    }

    [Fact]
    public void A_non_positive_target_is_rejected()
    {
        var calendar = new WorkingDayCalendar();

        var exception = Assert.Throws<DomainException>(() => SlaTarget.Start(calendar, SubmittedOn, 0));

        Assert.Equal("sla.target.nonPositive", exception.Code);
    }

    [Fact]
    public void Extending_never_overwrites_the_original_target()
    {
        var calendar = new WorkingDayCalendar();
        var target = SlaTarget.Start(calendar, SubmittedOn, 12);
        var original = target.OriginalTargetDate;

        target.Extend(original.AddDays(7), "Awaiting legal review of clause 4.");

        Assert.Equal(original, target.OriginalTargetDate);
        Assert.Equal(original.AddDays(7), target.CurrentTargetDate);
        Assert.True(target.IsExtended);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void Extending_without_a_reason_is_rejected(string reason)
    {
        var calendar = new WorkingDayCalendar();
        var target = SlaTarget.Start(calendar, SubmittedOn, 12);

        var exception = Assert.Throws<DomainException>(
            () => target.Extend(target.CurrentTargetDate.AddDays(1), reason));

        Assert.Equal("sla.extension.reasonRequired", exception.Code);
    }

    [Fact]
    public void An_extension_must_move_the_target_later()
    {
        var calendar = new WorkingDayCalendar();
        var target = SlaTarget.Start(calendar, SubmittedOn, 12);

        var exception = Assert.Throws<DomainException>(
            () => target.Extend(target.CurrentTargetDate.AddDays(-1), "Pulling the date forward."));

        Assert.Equal("sla.extension.notLater", exception.Code);
    }
}
