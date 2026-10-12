namespace Docaya.Application.Ports;

/// <summary>
/// Maintains the Document Index Record for published versions.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 12.4 and 12.6. Only approved,
/// published content is ever indexed. Results are trimmed at query time against the
/// caller's security keys; unauthorised items are removed, not masked.
/// </remarks>
public interface ISearchIndexPort
{
    /// <summary>
    /// Creates or replaces the index record for a published document version.
    /// </summary>
    /// <param name="documentId">The published document.</param>
    /// <param name="version">The published version number.</param>
    /// <param name="aclKeys">Permission keys used for trimming at query time.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the record has been indexed.</returns>
    Task IndexAsync(
        Guid documentId,
        int version,
        IReadOnlyCollection<string> aclKeys,
        CancellationToken cancellationToken);

    /// <summary>
    /// Refreshes the permission keys on existing index records.
    /// </summary>
    /// <param name="documentIds">Documents whose access has changed.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the keys have been refreshed.</returns>
    /// <remarks>Triggered by <c>AccessPolicyChanged</c> (TAD 24.3).</remarks>
    Task RefreshAclKeysAsync(IReadOnlyCollection<Guid> documentIds, CancellationToken cancellationToken);

    /// <summary>
    /// Removes a document version from the index.
    /// </summary>
    /// <param name="documentId">The document to remove.</param>
    /// <param name="version">The version to remove.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the record has been removed.</returns>
    Task RemoveAsync(Guid documentId, int version, CancellationToken cancellationToken);
}
