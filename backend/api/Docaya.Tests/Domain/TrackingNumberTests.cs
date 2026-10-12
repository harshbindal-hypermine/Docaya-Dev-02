using Docaya.Domain.Common;
using Docaya.Domain.Documents;

namespace Docaya.Tests.Domain;

/// <summary>
/// Verifies the <c>DOC-YYYY-NNNNNN</c> tracking number issued at capture.
/// </summary>
/// <remarks>Technical Architecture Document v1.3, Section 7.1 step 1.</remarks>
public class TrackingNumberTests
{
    [Fact]
    public void Is_formatted_as_doc_year_sequence()
    {
        var trackingNumber = TrackingNumber.Create(2026, 42);

        Assert.Equal("DOC-2026-000042", trackingNumber.Value);
        Assert.Equal(2026, trackingNumber.Year);
        Assert.Equal(42, trackingNumber.Sequence);
    }

    [Theory]
    [InlineData("DOC-2026-000042", 2026, 42)]
    [InlineData("DOC-2026-999999", 2026, 999999)]
    [InlineData("DOC-1999-000001", 1999, 1)]
    public void Round_trips_through_parse(string value, int year, int sequence)
    {
        var parsed = TrackingNumber.Parse(value);

        Assert.Equal(year, parsed.Year);
        Assert.Equal(sequence, parsed.Sequence);
        Assert.Equal(value, parsed.ToString());
    }

    [Theory]
    [InlineData("")]
    [InlineData("DOC-2026-42")]
    [InlineData("DOC-26-000042")]
    [InlineData("XXX-2026-000042")]
    [InlineData("DOC-2026-000000")]
    [InlineData("DOC-2026_000042")]
    [InlineData("doc-2026-000042")]
    [InlineData("DOC-2026-0000421")]
    public void Rejects_malformed_values(string value)
    {
        Assert.False(TrackingNumber.TryParse(value, out _));

        var exception = Assert.Throws<DomainException>(() => TrackingNumber.Parse(value));
        Assert.Equal("trackingNumber.malformed", exception.Code);
    }

    [Theory]
    [InlineData(2026, 0)]
    [InlineData(2026, 1_000_000)]
    [InlineData(999, 1)]
    [InlineData(10000, 1)]
    public void Rejects_out_of_range_components(int year, int sequence)
    {
        Assert.Throws<DomainException>(() => TrackingNumber.Create(year, sequence));
    }

    [Fact]
    public void Two_identical_tracking_numbers_are_equal()
    {
        Assert.Equal(TrackingNumber.Create(2026, 7), TrackingNumber.Create(2026, 7));
        Assert.NotEqual(TrackingNumber.Create(2026, 7), TrackingNumber.Create(2026, 8));
    }
}
