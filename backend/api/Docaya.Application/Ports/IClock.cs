namespace Docaya.Application.Ports;

/// <summary>
/// Supplies the current time.
/// </summary>
/// <remarks>
/// A port rather than a direct call to <see cref="DateTimeOffset.UtcNow"/> so that
/// working-day SLA behaviour is deterministically testable.
/// </remarks>
public interface IClock
{
    /// <summary>The current instant in UTC.</summary>
    DateTimeOffset UtcNow { get; }

    /// <summary>The current date in the organisation's operating time zone.</summary>
    DateOnly Today { get; }
}
