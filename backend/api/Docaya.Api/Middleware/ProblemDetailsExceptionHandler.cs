using Docaya.Domain.Common;
using Docaya.Domain.Documents;

using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace Docaya.Api.Middleware;

/// <summary>
/// Maps unhandled exceptions onto the single problem-detail envelope.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 6.3:
/// "A single problem-detail shape carries a machine-readable code, a human-readable
/// message, field-level validation detail and the correlation ID. Internal exception
/// text and stack traces are never returned."
/// </para>
/// <para>
/// Domain exceptions map to conflict or unprocessable responses (TAD 6.2). Anything
/// else becomes an opaque 500 - the detail is logged, never serialised to the caller.
/// </para>
/// </remarks>
public sealed partial class ProblemDetailsExceptionHandler : IExceptionHandler
{
    private const string ProblemTypeBase = "https://docaya.local/problems/";

    /// <summary>Non-standard status used when the client disconnects before completion.</summary>
    private const int ClientClosedRequest = 499;

    private readonly ILogger<ProblemDetailsExceptionHandler> _logger;

    /// <summary>Creates the handler.</summary>
    /// <param name="logger">Structured logger.</param>
    public ProblemDetailsExceptionHandler(ILogger<ProblemDetailsExceptionHandler> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Source-generated structured log for a mapped exception.
    /// </summary>
    /// <param name="logger">The logger.</param>
    /// <param name="status">HTTP status the exception was mapped to.</param>
    /// <param name="code">Stable machine-readable error code.</param>
    /// <param name="correlationId">W3C trace correlation identifier.</param>
    /// <param name="exception">The exception being handled.</param>
    [LoggerMessage(
        EventId = 1000,
        Level = LogLevel.Error,
        Message = "Unhandled exception mapped to {Status} {Code}. CorrelationId={CorrelationId}")]
    static partial void LogMappedException(
        ILogger logger,
        int status,
        string code,
        string correlationId,
        Exception exception);


    /// <inheritdoc />
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(httpContext);
        ArgumentNullException.ThrowIfNull(exception);

        var correlationId = CorrelationMiddleware.ResolveCorrelationId(httpContext);
        var (status, code, title, detail) = Translate(exception);

        // The full exception is logged with the correlation ID. Only the safe
        // envelope is written to the response.
        LogMappedException(_logger, status, code, correlationId, exception);

        var problem = new ProblemDetails
        {
            Type = ProblemTypeBase + code,
            Title = title,
            Status = status,
            Detail = detail,
            Instance = httpContext.Request.Path,
        };

        problem.Extensions["code"] = code;
        problem.Extensions["correlationId"] = correlationId;

        httpContext.Response.StatusCode = status;
        httpContext.Response.ContentType = "application/problem+json";

        await httpContext.Response.WriteAsJsonAsync(problem, cancellationToken);
        return true;
    }

    private static (int Status, string Code, string Title, string Detail) Translate(Exception exception) =>
        exception switch
        {
            IllegalTransitionException transition => (
                StatusCodes.Status409Conflict,
                transition.Code,
                "Illegal state transition",
                transition.Message),

            DomainException domain => (
                StatusCodes.Status422UnprocessableEntity,
                domain.Code,
                "Domain invariant violated",
                domain.Message),

            // Cancellation is a client disconnect, not a server fault.
            OperationCanceledException => (
                ClientClosedRequest,
                "request.cancelled",
                "Request cancelled",
                "The request was cancelled before it completed."),

            _ => (
                StatusCodes.Status500InternalServerError,
                "server.unexpected",
                "Unexpected error",
                "The request could not be completed. Quote the correlation ID when reporting this."),
        };
}
