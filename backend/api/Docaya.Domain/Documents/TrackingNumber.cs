using Docaya.Domain.Common;

namespace Docaya.Domain.Documents;

/// <summary>
/// The document tracking number issued at capture, in the form <c>DOC-YYYY-NNNNNN</c>.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 7.1 step 1. The tracking number is
/// issued once, at capture, and never changes across revisions.
/// </remarks>
public readonly record struct TrackingNumber
{
    /// <summary>The highest sequence number representable in six digits.</summary>
    public const int MaxSequence = 999_999;

    private TrackingNumber(int year, int sequence, string value)
    {
        Year = year;
        Sequence = sequence;
        Value = value;
    }

    /// <summary>The four-digit year component.</summary>
    public int Year { get; }

    /// <summary>The six-digit sequence component.</summary>
    public int Sequence { get; }

    /// <summary>The canonical string form, for example <c>DOC-2026-000042</c>.</summary>
    public string Value { get; }

    /// <summary>
    /// Creates a tracking number from its year and sequence components.
    /// </summary>
    /// <param name="year">Four-digit year.</param>
    /// <param name="sequence">Sequence within the year, from 1 to <see cref="MaxSequence"/>.</param>
    /// <returns>The created tracking number.</returns>
    /// <exception cref="DomainException">The year or sequence is outside the representable range.</exception>
    public static TrackingNumber Create(int year, int sequence)
    {
        if (year is < 1000 or > 9999)
        {
            throw new DomainException(
                "trackingNumber.year.outOfRange",
                "A tracking number year must be four digits.");
        }

        if (sequence is < 1 or > MaxSequence)
        {
            throw new DomainException(
                "trackingNumber.sequence.outOfRange",
                $"A tracking number sequence must be between 1 and {MaxSequence}.");
        }

        return new TrackingNumber(year, sequence, $"DOC-{year:D4}-{sequence:D6}");
    }

    /// <summary>
    /// Parses a canonical tracking number.
    /// </summary>
    /// <param name="value">The string to parse.</param>
    /// <returns>The parsed tracking number.</returns>
    /// <exception cref="DomainException">The value is not a canonical tracking number.</exception>
    public static TrackingNumber Parse(string value)
    {
        if (!TryParse(value, out var trackingNumber))
        {
            throw new DomainException(
                "trackingNumber.malformed",
                "A tracking number must be in the form DOC-YYYY-NNNNNN.");
        }

        return trackingNumber;
    }

    /// <summary>
    /// Attempts to parse a canonical tracking number.
    /// </summary>
    /// <param name="value">The string to parse.</param>
    /// <param name="trackingNumber">The parsed tracking number when parsing succeeds.</param>
    /// <returns><c>true</c> when <paramref name="value"/> is a canonical tracking number.</returns>
    public static bool TryParse(string? value, out TrackingNumber trackingNumber)
    {
        trackingNumber = default;

        if (string.IsNullOrEmpty(value) || value.Length != 15)
        {
            return false;
        }

        if (!value.StartsWith("DOC-", StringComparison.Ordinal) || value[8] != '-')
        {
            return false;
        }

        var yearSpan = value.AsSpan(4, 4);
        var sequenceSpan = value.AsSpan(9, 6);

        if (!int.TryParse(yearSpan, out var year) || !int.TryParse(sequenceSpan, out var sequence))
        {
            return false;
        }

        if (year is < 1000 or > 9999 || sequence is < 1 or > MaxSequence)
        {
            return false;
        }

        trackingNumber = new TrackingNumber(year, sequence, value);
        return true;
    }

    /// <inheritdoc />
    public override string ToString() => Value;
}
