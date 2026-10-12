using Docaya.Application.Ports;

namespace Docaya.Infrastructure.Adapters;

/// <summary>
/// Local fail-closed adapter set used until the Azure provider adapters are configured.
/// </summary>
public sealed class AuditWriter : IAuditWriter
{
    public Task AppendAsync(AuditEntry entry, CancellationToken cancellationToken) => Task.CompletedTask;
}

public sealed class AuthorizationPolicyEvaluator : IAuthorizationPolicyEvaluator
{
    private const string PolicyVersion = "readiness-placeholder-v1";

    public Task<AuthorizationDecision> EvaluateAsync(
        string action,
        Guid? resourceId,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(action);
        return Task.FromResult(AuthorizationDecision.Deny(PolicyVersion, "provider-adapter-not-configured"));
    }

    public Task<IReadOnlyCollection<string>> GetSecurityKeysAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyCollection<string>>(Array.Empty<string>());
}

public sealed class ContentPromoter : IContentPromoter
{
    public Task<PromotionResult> PromoteAsync(
        Guid documentId,
        string targetSiteId,
        string targetDriveId,
        string fileName,
        Stream content,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(targetSiteId);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetDriveId);
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        ArgumentNullException.ThrowIfNull(content);

        return Task.FromException<PromotionResult>(
            new InvalidOperationException("The SharePoint content promotion adapter is not configured."));
    }
}

public sealed class EventPublisher : IEventPublisher
{
    public Task EnqueueAsync(OutboxEvent outboxEvent, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(outboxEvent.EventType);
        ArgumentException.ThrowIfNullOrWhiteSpace(outboxEvent.IdempotencyKey);
        return Task.CompletedTask;
    }
}

public sealed class IdempotencyStore : IIdempotencyStore
{
    private readonly Dictionary<string, string> _entries = new(StringComparer.Ordinal);

    public Task<string?> TryGetAsync(string key, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        return Task.FromResult(_entries.GetValueOrDefault(key));
    }

    public Task RecordAsync(string key, string resultPayload, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(key);
        ArgumentNullException.ThrowIfNull(resultPayload);

        _entries.TryAdd(key, resultPayload);
        return Task.CompletedTask;
    }
}

public sealed class SearchIndexPort : ISearchIndexPort
{
    public Task IndexAsync(
        Guid documentId,
        int version,
        IReadOnlyCollection<string> aclKeys,
        CancellationToken cancellationToken) => Task.CompletedTask;

    public Task RefreshAclKeysAsync(IReadOnlyCollection<Guid> documentIds, CancellationToken cancellationToken) =>
        Task.CompletedTask;

    public Task RemoveAsync(Guid documentId, int version, CancellationToken cancellationToken) => Task.CompletedTask;
}

public sealed class StagingContentStore : IStagingContentStore
{
    public Task<long> AppendChunkAsync(
        string uploadId,
        long offset,
        Stream content,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uploadId);
        ArgumentNullException.ThrowIfNull(content);
        return Task.FromResult(offset + content.Length);
    }

    public Task<string> CompleteAsync(string uploadId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uploadId);
        return Task.FromException<string>(
            new InvalidOperationException("The staging content store adapter is not configured."));
    }

    public Task<Stream> OpenReadAsync(string uploadId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uploadId);
        return Task.FromException<Stream>(
            new InvalidOperationException("The staging content store adapter is not configured."));
    }

    public Task PurgeAsync(string uploadId, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uploadId);
        return Task.CompletedTask;
    }
}

public sealed class UnitOfWork : IUnitOfWork
{
    public Task<int> CommitAsync(CancellationToken cancellationToken) => Task.FromResult(0);
}
