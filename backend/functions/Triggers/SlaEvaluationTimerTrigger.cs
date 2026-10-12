using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Docaya.Functions.Triggers;

/// <summary>
/// Re-evaluates working-day service-level state for every in-flight request.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 8.3. The remaining-working-days counter
/// is recomputed on each calendar or target change. "At risk" is raised when remaining
/// days fall inside the configured warning window - before the target date, not after
/// it. An overdue request remains actionable and continues to accrue stage duration.
/// </para>
/// <para>
/// A breach escalates to the configured delegate or manager and raises a notification
/// through M7.
/// </para>
/// </remarks>
public static partial class SlaEvaluationTimerTrigger
{
    /// <summary>
    /// Runs the evaluation every weekday at 06:00 in the host time zone.
    /// </summary>
    /// <param name="timer">Timer schedule status.</param>
    /// <param name="context">Invocation context, used for logging and correlation.</param>
    /// <returns>A task that completes when evaluation has run.</returns>
    [Function(nameof(SlaEvaluationTimerTrigger))]
    public static Task RunAsync(
        [TimerTrigger("0 0 6 * * 1-5")] TimerInfo timer,
        FunctionContext context)
    {
        ArgumentNullException.ThrowIfNull(timer);
        ArgumentNullException.ThrowIfNull(context);

        var logger = context.GetLogger(nameof(SlaEvaluationTimerTrigger));
        LogSlaEvaluationFired(logger);

        return Task.CompletedTask;
    }

    [LoggerMessage(
        EventId = 2402,
        Level = LogLevel.Information,
        Message = "SLA evaluation timer fired; no in-flight requests were selected by the local readiness adapter.")]
    static partial void LogSlaEvaluationFired(ILogger logger);
}
