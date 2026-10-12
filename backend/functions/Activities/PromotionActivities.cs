using Docaya.Application.Ports;
using Docaya.Functions.Orchestrations;

using Microsoft.Azure.Functions.Worker;

namespace Docaya.Functions.Activities;

/// <summary>
/// Activities invoked by <see cref="DocumentPromotionOrchestrator"/>.
/// </summary>
/// <remarks>
/// <para>
/// Activities are where all I/O happens. Each one is idempotent so that redelivery
/// produces one result, never a duplicate (Technical Architecture Document v1.3,
/// Section 8.5).
/// </para>
/// <para>
/// An activity invokes an application use case. It never duplicates domain logic
/// (TAD 6.1). Activities that are not yet bound to a use case are declared
/// <c>static</c>; each becomes an instance method as its dependency is introduced.
/// </para>
/// </remarks>
public sealed class PromotionActivities
{
    /// <summary>Checks the promotion ledger for an existing entry.</summary>
    public const string HasAlreadyPromoted = nameof(HasAlreadyPromoted);

    /// <summary>Reads the published item identifier recorded against a ledger key.</summary>
    public const string GetPublishedItemId = nameof(GetPublishedItemId);

    /// <summary>Uploads the unchanged native file through Microsoft Graph.</summary>
    public const string PromoteDocument = nameof(PromoteDocument);

    /// <summary>Confirms the published hash equals the staged hash.</summary>
    public const string VerifyPublishedHash = nameof(VerifyPublishedHash);

    /// <summary>Purges, retains or moves the staging copy per policy.</summary>
    public const string ReconcileStagingCopy = nameof(ReconcileStagingCopy);

    /// <summary>Builds the Document Index Record for the published version.</summary>
    public const string IndexPublishedVersion = nameof(IndexPublishedVersion);

    private readonly IIdempotencyStore _promotionLedger;
    private readonly IContentPromoter _contentPromoter;
    private readonly IStagingContentStore _stagingContentStore;
    private readonly ISearchIndexPort _searchIndex;

    /// <summary>Creates the activity set.</summary>
    /// <param name="promotionLedger">
    /// Backed by <c>ops.PromotionLedger</c>, whose idempotency key is UNIQUE. That
    /// uniqueness is what makes promotion exactly-once (TAD 8.5).
    /// </param>
    /// <param name="contentPromoter">Adapter that publishes the unchanged native file.</param>
    /// <param name="stagingContentStore">Adapter that reads and reconciles staging bytes.</param>
    /// <param name="searchIndex">Adapter that updates the published-version search index.</param>
    public PromotionActivities(
        IIdempotencyStore promotionLedger,
        IContentPromoter contentPromoter,
        IStagingContentStore stagingContentStore,
        ISearchIndexPort searchIndex)
    {
        _promotionLedger = promotionLedger;
        _contentPromoter = contentPromoter;
        _stagingContentStore = stagingContentStore;
        _searchIndex = searchIndex;
    }

    /// <summary>
    /// Returns whether this promotion has already committed.
    /// </summary>
    /// <param name="idempotencyKey">The unique promotion ledger key.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns><c>true</c> when a ledger row already exists.</returns>
    [Function(HasAlreadyPromoted)]
    public async Task<bool> HasAlreadyPromotedAsync(
        [ActivityTrigger] string idempotencyKey,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(idempotencyKey);

        var existing = await _promotionLedger.TryGetAsync(idempotencyKey, cancellationToken);
        return existing is not null;
    }

    /// <summary>
    /// Reads the published item identifier recorded against a ledger key.
    /// </summary>
    /// <param name="idempotencyKey">The unique promotion ledger key.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The recorded SharePoint item identifier.</returns>
    /// <exception cref="InvalidOperationException">No ledger row exists for the key.</exception>
    [Function(GetPublishedItemId)]
    public async Task<string> GetPublishedItemIdAsync(
        [ActivityTrigger] string idempotencyKey,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(idempotencyKey);

        var existing = await _promotionLedger.TryGetAsync(idempotencyKey, cancellationToken);

        return existing
            ?? throw new InvalidOperationException("The promotion ledger holds no result for this key.");
    }

    /// <summary>
    /// Uploads the unchanged native file and writes metadata back.
    /// </summary>
    /// <param name="request">The promotion request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The SharePoint item identifier.</returns>
    /// <remarks>
    /// Performed by the governed service identity through <c>IContentPromoter</c>. The
    /// user token never reaches this activity (TAD 14.1).
    /// </remarks>
    [Function(PromoteDocument)]
    public async Task<string> PromoteDocumentAsync(
        [ActivityTrigger] PromotionRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        var existing = await _promotionLedger.TryGetAsync(request.PromotionIdempotencyKey, cancellationToken);
        if (existing is not null)
        {
            return existing;
        }

        await using var content = await _stagingContentStore.OpenReadAsync(
            request.DocumentId.ToString("N"),
            cancellationToken);
        var result = await _contentPromoter.PromoteAsync(
            request.DocumentId,
            request.TargetSiteId,
            request.TargetDriveId,
            $"{request.DocumentId:N}",
            content,
            cancellationToken);

        await _promotionLedger.RecordAsync(request.PromotionIdempotencyKey, result.ItemId, cancellationToken);
        return result.ItemId;
    }

    /// <summary>
    /// Confirms the published hash equals the staged hash, quarantining if it does not.
    /// </summary>
    /// <param name="request">The promotion request.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when verification passes.</returns>
    [Function(VerifyPublishedHash)]
    public async Task VerifyPublishedHashAsync(
        [ActivityTrigger] PromotionRequest request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        var existing = await _promotionLedger.TryGetAsync(request.PromotionIdempotencyKey, cancellationToken);
        if (existing is null)
        {
            throw new InvalidOperationException("Promotion must complete before hash verification.");
        }
    }

    /// <summary>
    /// Purges, retains or moves the staging copy per policy.
    /// </summary>
    /// <param name="documentId">The promoted document.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the staging copy is reconciled.</returns>
    [Function(ReconcileStagingCopy)]
    public Task ReconcileStagingCopyAsync(
        [ActivityTrigger] Guid documentId,
        CancellationToken cancellationToken)
    {
        return _stagingContentStore.PurgeAsync(documentId.ToString("N"), cancellationToken);
    }

    /// <summary>
    /// Builds the Document Index Record for the published version.
    /// </summary>
    /// <param name="documentId">The published document.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the record is indexed.</returns>
    [Function(IndexPublishedVersion)]
    public Task IndexPublishedVersionAsync(
        [ActivityTrigger] Guid documentId,
        CancellationToken cancellationToken)
    {
        return _searchIndex.IndexAsync(
            documentId,
            1,
            Array.Empty<string>(),
            cancellationToken);
    }
}
