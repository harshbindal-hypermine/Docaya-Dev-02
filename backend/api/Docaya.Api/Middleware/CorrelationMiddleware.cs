using System.Diagnostics;

namespace Docaya.Api.Middleware;

/// <summary>
/// Attaches or propagates the W3C trace-context correlation identifier.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Sections 6.2 and 24.1. The correlation ID
/// flows from the browser through the API, the queue, the worker and into the audit
/// record. This stage never fails a request - it is always applied.
/// </remarks>
public sealed class CorrelationMiddleware
{
    /// <summary>Response header carrying the correlation identifier back to the caller.</summary>
    public const string HeaderName = "X-Correlation-Id";

    private readonly RequestDelegate _next;

    /// <summary>Creates the middleware.</summary>
    /// <param name="next">The next delegate in the pipeline.</param>
    public CorrelationMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    /// <summary>Runs the middleware.</summary>
    /// <param name="context">The current HTTP context.</param>
    /// <returns>A task that completes when the pipeline has run.</returns>
    public async Task InvokeAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        var correlationId = ResolveCorrelationId(context);
        context.Items[HeaderName] = correlationId;

        context.Response.OnStarting(() =>
        {
            context.Response.Headers[HeaderName] = correlationId;
            return Task.CompletedTask;
        });

        await _next(context);
    }

    /// <summary>
    /// Reads the correlation identifier for the current request.
    /// </summary>
    /// <param name="context">The current HTTP context.</param>
    /// <returns>The correlation identifier, which is always present.</returns>
    public static string ResolveCorrelationId(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (context.Items.TryGetValue(HeaderName, out var existing) && existing is string cached)
        {
            return cached;
        }

        // Prefer the ambient Activity so the identifier matches the distributed trace.
        var traceId = Activity.Current?.TraceId.ToString();
        if (!string.IsNullOrEmpty(traceId))
        {
            return traceId;
        }

        if (context.Request.Headers.TryGetValue(HeaderName, out var supplied))
        {
            var value = supplied.ToString();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return context.TraceIdentifier;
    }
}
