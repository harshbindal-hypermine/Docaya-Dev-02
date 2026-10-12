using Docaya.Functions.Activities;

using Microsoft.Azure.Functions.Worker;
using Microsoft.DurableTask;

namespace Docaya.Functions.Orchestrations;

/// <summary>
/// Input to the promotion orchestration.
/// </summary>
/// <param name="DocumentId">The approved document to promote.</param>
/// <param name="PromotionIdempotencyKey">
/// Unique key enforcing exactly-once promotion through <c>ops.PromotionLedger</c>.
/// </param>
/// <param name="TargetSiteId">Resolved target SharePoint site.</param>
/// <param name="TargetDriveId">Resolved target library drive.</param>
/// <param name="StagedSha256">Hash of the staged file, which the published hash must equal.</param>
public sealed record PromotionRequest(
    Guid DocumentId,
    string PromotionIdempotencyKey,
    string TargetSiteId,
    string TargetDriveId,
    string StagedSha256);

/// <summary>
/// Promotes an approved document into SharePoint Online.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 7.1 steps 6 to 9, and Section 8.5.
/// </para>
/// <para>
/// An orchestrator body must be deterministic and replay-safe: it performs no I/O, uses
/// no ambient clock or random source, and reaches every external system through an
/// activity. A generated orchestration is never merged without a replay test (TAD 17.7).
/// </para>
/// </remarks>
public static class DocumentPromotionOrchestrator
{
    /// <summary>Name under which the orchestration is registered.</summary>
    public const string Name = nameof(DocumentPromotionOrchestrator);

    /// <summary>
    /// Runs the promotion orchestration.
    /// </summary>
    /// <param name="context">Durable orchestration context.</param>
    /// <returns>The published item identifier.</returns>
    [Function(Name)]
    public static async Task<string> RunAsync(
        [OrchestrationTrigger] TaskOrchestrationContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var request = context.GetInput<PromotionRequest>()
            ?? throw new InvalidOperationException("Promotion orchestration requires input.");

        // Exactly-once promotion. The ledger key is UNIQUE, so a retried promotion finds
        // the existing row and stops rather than writing a duplicate (TAD 8.5).
        var alreadyPromoted = await context.CallActivityAsync<bool>(
            PromotionActivities.HasAlreadyPromoted,
            request.PromotionIdempotencyKey);

        if (alreadyPromoted)
        {
            return await context.CallActivityAsync<string>(
                PromotionActivities.GetPublishedItemId,
                request.PromotionIdempotencyKey);
        }

        // Upload the unchanged native file under the governed service identity, then
        // write site, drive, item, URL, version and published hash back.
        var publishedItemId = await context.CallActivityAsync<string>(
            PromotionActivities.PromoteDocument,
            request);

        // The published hash must equal the staged hash or the promotion is quarantined
        // rather than completed (TAD 7.2).
        await context.CallActivityAsync(PromotionActivities.VerifyPublishedHash, request);

        // Purge, retain or move the staging copy per policy. A failed promotion is
        // retained and replayable (TAD 7.1 step 8).
        await context.CallActivityAsync(PromotionActivities.ReconcileStagingCopy, request.DocumentId);

        // Build the Document Index Record. Only approved, published content is indexed.
        await context.CallActivityAsync(PromotionActivities.IndexPublishedVersion, request.DocumentId);

        return publishedItemId;
    }
}
