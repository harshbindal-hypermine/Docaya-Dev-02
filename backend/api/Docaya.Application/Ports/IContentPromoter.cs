namespace Docaya.Application.Ports;

/// <summary>
/// The outcome of promoting a document into its SharePoint library.
/// </summary>
/// <param name="SiteId">SharePoint site identifier.</param>
/// <param name="DriveId">SharePoint drive identifier.</param>
/// <param name="ItemId">SharePoint item identifier.</param>
/// <param name="WebUrl">Browser URL of the published item.</param>
/// <param name="SharePointVersion">Native version label assigned by SharePoint.</param>
/// <param name="PublishedSha256">SHA-256 of the published file.</param>
public readonly record struct PromotionResult(
    string SiteId,
    string DriveId,
    string ItemId,
    string? WebUrl,
    string? SharePointVersion,
    string PublishedSha256);

/// <summary>
/// Promotes an approved document into SharePoint Online and writes metadata back.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 7.1 step 7: the promotion worker
/// uploads the same native file through Microsoft Graph under the governed service
/// identity, then writes back site, drive, item, URL, version and the published hash.
/// </para>
/// <para>
/// On-Behalf-Of access was deleted in v1.3. The user token stops at the Docaya API and
/// is never forwarded; a governed service identity performs all content operations
/// (TAD 14.1, 14.6.1).
/// </para>
/// </remarks>
public interface IContentPromoter
{
    /// <summary>
    /// Uploads the unchanged native file and writes the metadata columns back.
    /// </summary>
    /// <param name="documentId">The document being promoted.</param>
    /// <param name="targetSiteId">Resolved target site.</param>
    /// <param name="targetDriveId">Resolved target library drive.</param>
    /// <param name="fileName">File name to write.</param>
    /// <param name="content">The unchanged staged byte stream.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The write-back details for the published item.</returns>
    Task<PromotionResult> PromoteAsync(
        Guid documentId,
        string targetSiteId,
        string targetDriveId,
        string fileName,
        Stream content,
        CancellationToken cancellationToken);
}
