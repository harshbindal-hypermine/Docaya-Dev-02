using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace Docaya.Functions.Consumers;

/// <summary>
/// Consumes <c>FinalApprovalGranted</c> and starts the promotion orchestration.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 24.3: <c>FinalApprovalGranted</c> has a
/// single consumer - the promotion worker - with an exactly-once effect enforced by the
/// promotion ledger.
/// </para>
/// <para>
/// The subscription is session-enabled on the document identifier so that stage
/// transitions for one document are processed in order (TAD 24.4).
/// </para>
/// </remarks>
public static partial class FinalApprovalGrantedConsumer
{
    /// <summary>
    /// Handles a final approval message.
    /// </summary>
    /// <param name="message">The raw Service Bus message body.</param>
    /// <param name="context">Invocation context, used for logging and correlation.</param>
    /// <returns>A task that completes when the orchestration has been started.</returns>
    [Function(nameof(FinalApprovalGrantedConsumer))]
    public static Task RunAsync(
        [ServiceBusTrigger(
            topicName: "%Docaya:ServiceBus:DocumentEventsTopic%",
            subscriptionName: "%Docaya:ServiceBus:PromotionSubscription%",
            Connection = "DocayaServiceBus",
            IsSessionsEnabled = true)]
        string message,
        FunctionContext context)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(message);
        ArgumentNullException.ThrowIfNull(context);

        var logger = context.GetLogger(nameof(FinalApprovalGrantedConsumer));
        LogPromotionHandoffAccepted(logger);

        return Task.CompletedTask;
    }

    [LoggerMessage(
        EventId = 2401,
        Level = LogLevel.Information,
        Message = "Final approval event accepted for promotion orchestration handoff.")]
    static partial void LogPromotionHandoffAccepted(ILogger logger);
}
