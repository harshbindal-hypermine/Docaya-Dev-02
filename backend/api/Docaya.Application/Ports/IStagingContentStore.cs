namespace Docaya.Application.Ports;

/// <summary>
/// Reads and writes the unchanged document byte stream in the controlled staging zone.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 7.1 step 1. The byte stream is
/// written to staging unchanged; there is no file-format conversion at any step.
/// Implemented in Infrastructure by the Azure Blob Storage adapter under a workload
/// identity (TAD 14.6.2).
/// </remarks>
public interface IStagingContentStore
{
    /// <summary>
    /// Appends a chunk of a resumable upload.
    /// </summary>
    /// <param name="uploadId">Identifier of the upload session.</param>
    /// <param name="offset">Byte offset at which this chunk begins.</param>
    /// <param name="content">The chunk content.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The total number of bytes received so far.</returns>
    Task<long> AppendChunkAsync(
        string uploadId,
        long offset,
        Stream content,
        CancellationToken cancellationToken);

    /// <summary>
    /// Finalises an upload and computes the SHA-256 of the assembled file.
    /// </summary>
    /// <param name="uploadId">Identifier of the upload session.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The lowercase hexadecimal SHA-256 of the staged file.</returns>
    Task<string> CompleteAsync(string uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Opens the staged file for reading.
    /// </summary>
    /// <param name="uploadId">Identifier of the upload session.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A readable stream over the unchanged staged bytes.</returns>
    Task<Stream> OpenReadAsync(string uploadId, CancellationToken cancellationToken);

    /// <summary>
    /// Purges, retains or moves the staging copy after reconciliation.
    /// </summary>
    /// <param name="uploadId">Identifier of the upload session.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the staging copy has been reconciled.</returns>
    /// <remarks>A failed promotion is retained and replayable (TAD 7.1 step 8).</remarks>
    Task PurgeAsync(string uploadId, CancellationToken cancellationToken);
}
