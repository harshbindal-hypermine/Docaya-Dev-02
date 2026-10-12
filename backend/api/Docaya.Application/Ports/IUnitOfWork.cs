namespace Docaya.Application.Ports;

/// <summary>
/// Commits a set of changes and their outbox events atomically.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 8.5 - transactional outbox. The state
/// change and its domain event commit in one SQL transaction.
/// </remarks>
public interface IUnitOfWork
{
    /// <summary>
    /// Commits all pending changes and enlisted events in a single transaction.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The number of state entries written.</returns>
    Task<int> CommitAsync(CancellationToken cancellationToken);
}
