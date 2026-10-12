using Docaya.Application.Ports;

namespace Docaya.Infrastructure.Adapters;

/// <summary>
/// Supplies the current time from the system clock.
/// </summary>
/// <remarks>
/// The operating time zone is configurable so that working-day SLA arithmetic is
/// evaluated against the client's local calendar rather than UTC.
/// </remarks>
public sealed class SystemClock : IClock
{
    private readonly TimeZoneInfo _operatingTimeZone;

    /// <summary>
    /// Creates a clock.
    /// </summary>
    /// <param name="operatingTimeZone">
    /// The organisation's operating time zone. Defaults to UTC when not supplied.
    /// </param>
    public SystemClock(TimeZoneInfo? operatingTimeZone = null)
    {
        _operatingTimeZone = operatingTimeZone ?? TimeZoneInfo.Utc;
    }

    /// <inheritdoc />
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;

    /// <inheritdoc />
    public DateOnly Today =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, _operatingTimeZone).Date);
}
