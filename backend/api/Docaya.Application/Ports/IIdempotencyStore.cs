namespace Docaya.Application.Ports;

/// <summary>
/// Records and replays idempotent write results.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 6.2 and 24.1: every write carries an
/// idempotency key, and a duplicate request returns the original result rather than
/// repeating the effect.
/// </remarks>
public interface IIdempotencyStore
{
    /// <summary>
    /// Looks up a previously recorded result for an idempotency key.
    /// </summary>
    /// <param name="key">The idempotency key.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The recorded result payload, or <c>null</c> when the key is unseen.</returns>
    Task<string?> TryGetAsync(string key, CancellationToken cancellationToken);

    /// <summary>
    /// Records the result of a write against its idempotency key.
    /// </summary>
    /// <param name="key">The idempotency key.</param>
    /// <param name="resultPayload">The serialised result to replay on redelivery.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the result has been recorded.</returns>
    Task RecordAsync(string key, string resultPayload, CancellationToken cancellationToken);
}
