namespace Docaya.Functions.Shared;

/// <summary>
/// Builds the idempotency keys that make redelivery safe.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 8.5 and 24.4: every write carries an
/// idempotency key, and a redelivered message produces one result, never a duplicate.
/// Keys are derived deterministically so the same logical effect always yields the same
/// key, whichever worker instance computes it.
/// </remarks>
public static class IdempotencyKeys
{
    /// <summary>
    /// Builds the exactly-once promotion key for a document version.
    /// </summary>
    /// <param name="documentId">The document being promoted.</param>
    /// <param name="version">The version being promoted.</param>
    /// <returns>A deterministic key for <c>ops.PromotionLedger</c>.</returns>
    public static string ForPromotion(Guid documentId, int version) =>
        $"promotion:{documentId:D}:{version}";

    /// <summary>
    /// Builds the key for indexing a published version.
    /// </summary>
    /// <param name="documentId">The published document.</param>
    /// <param name="version">The published version.</param>
    /// <returns>A deterministic key.</returns>
    public static string ForIndexing(Guid documentId, int version) =>
        $"index:{documentId:D}:{version}";

    /// <summary>
    /// Builds the key for a notification dispatch.
    /// </summary>
    /// <param name="eventId">The originating event identifier.</param>
    /// <param name="recipientId">The recipient principal.</param>
    /// <returns>A deterministic key.</returns>
    public static string ForNotification(Guid eventId, Guid recipientId) =>
        $"notify:{eventId:D}:{recipientId:D}";
}
