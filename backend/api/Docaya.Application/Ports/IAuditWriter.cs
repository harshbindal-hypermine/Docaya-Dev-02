namespace Docaya.Application.Ports;

/// <summary>
/// An entry appended to the hash-chained audit.
/// </summary>
/// <param name="Action">The action performed, for example <c>document.submitted</c>.</param>
/// <param name="Actor">The principal that requested the action.</param>
/// <param name="Executor">
/// The identity that actually performed the operation. For content operations this is
/// the governed service identity, not the signed-in user (TAD 14.1).
/// </param>
/// <param name="Outcome">Whether the action succeeded or was denied.</param>
/// <param name="CorrelationId">W3C trace correlation identifier.</param>
/// <param name="ResourceId">The resource acted upon, when applicable.</param>
public readonly record struct AuditEntry(
    string Action,
    string Actor,
    string Executor,
    string Outcome,
    string CorrelationId,
    Guid? ResourceId);

/// <summary>
/// Appends entries to the hash-chained audit.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 6.2 and 11.9.1. Audit failure is an
/// incident; the response to the caller is still safe. No document content, personal
/// data or secret is ever written to the audit payload.
/// </remarks>
public interface IAuditWriter
{
    /// <summary>
    /// Appends an entry to the audit chain.
    /// </summary>
    /// <param name="entry">The entry to append.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the entry has been appended.</returns>
    Task AppendAsync(AuditEntry entry, CancellationToken cancellationToken);
}
