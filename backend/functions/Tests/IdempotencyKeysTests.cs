using Docaya.Functions.Shared;

namespace Docaya.Functions.Tests;

/// <summary>
/// Verifies that idempotency keys are deterministic.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 8.5 and 24.4. A redelivered message
/// must produce one result, never a duplicate. That guarantee depends on the same
/// logical effect always deriving the same key, whichever worker instance computes it.
/// </remarks>
public class IdempotencyKeysTests
{
    private static readonly Guid DocumentId = new("6f9619ff-8b86-d011-b42d-00c04fc964ff");

    [Fact]
    public void Promotion_key_is_deterministic()
    {
        Assert.Equal(
            IdempotencyKeys.ForPromotion(DocumentId, 1),
            IdempotencyKeys.ForPromotion(DocumentId, 1));
    }

    [Fact]
    public void Promotion_key_differs_per_version()
    {
        Assert.NotEqual(
            IdempotencyKeys.ForPromotion(DocumentId, 1),
            IdempotencyKeys.ForPromotion(DocumentId, 2));
    }

    [Fact]
    public void Promotion_key_differs_per_document()
    {
        Assert.NotEqual(
            IdempotencyKeys.ForPromotion(DocumentId, 1),
            IdempotencyKeys.ForPromotion(Guid.NewGuid(), 1));
    }

    [Fact]
    public void Keys_for_different_effects_never_collide()
    {
        var promotion = IdempotencyKeys.ForPromotion(DocumentId, 1);
        var indexing = IdempotencyKeys.ForIndexing(DocumentId, 1);

        Assert.NotEqual(promotion, indexing);
    }

    [Fact]
    public void Notification_key_is_deterministic_per_recipient()
    {
        var eventId = Guid.NewGuid();
        var recipient = Guid.NewGuid();

        Assert.Equal(
            IdempotencyKeys.ForNotification(eventId, recipient),
            IdempotencyKeys.ForNotification(eventId, recipient));

        Assert.NotEqual(
            IdempotencyKeys.ForNotification(eventId, recipient),
            IdempotencyKeys.ForNotification(eventId, Guid.NewGuid()));
    }
}
