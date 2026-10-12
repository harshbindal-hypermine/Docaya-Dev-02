namespace Docaya.Application.Ports;

/// <summary>
/// A domain event awaiting dispatch through the transactional outbox.
/// </summary>
/// <param name="EventType">Catalogued event name from TAD 24.3.</param>
/// <param name="Payload">Event-specific payload, serialised by the adapter.</param>
/// <param name="IdempotencyKey">Key that makes redelivery safe for consumers.</param>
/// <param name="SessionId">
/// Set to the document identifier where ordering matters, so stage transitions for one
/// document are processed in order (TAD 24.4).
/// </param>
public readonly record struct OutboxEvent(
    string EventType,
    object Payload,
    string IdempotencyKey,
    string? SessionId);

/// <summary>
/// Enqueues domain events onto the transactional outbox.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 8.5 and 24.4: the state change and
/// its domain event are written in a single SQL transaction and dispatched afterwards,
/// so an event can never describe a state that did not persist, and a document can
/// never reach Approved without the promotion event being raised.
/// </remarks>
public interface IEventPublisher
{
    /// <summary>
    /// Enlists an event in the current unit of work.
    /// </summary>
    /// <param name="outboxEvent">The event to enqueue.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>A task that completes when the event has been enlisted.</returns>
    /// <remarks>
    /// The event is not dispatched here. It is committed with the state change and
    /// dispatched afterwards by the outbox processor.
    /// </remarks>
    Task EnqueueAsync(OutboxEvent outboxEvent, CancellationToken cancellationToken);
}
