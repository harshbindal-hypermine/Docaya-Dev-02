namespace Docaya.Functions.Configuration;

/// <summary>
/// Service Bus topic and subscription names.
/// </summary>
/// <remarks>
/// Bound from configuration so a deployment can rename entities without a code change.
/// Technical Architecture Document v1.3, Section 24.4.
/// </remarks>
public sealed class ServiceBusOptions
{
    /// <summary>Configuration section name.</summary>
    public const string SectionName = "Docaya:ServiceBus";

    /// <summary>Topic carrying the domain event catalogue.</summary>
    public string DocumentEventsTopic { get; init; } = "docaya-document-events";

    /// <summary>Subscription consumed by the promotion worker.</summary>
    public string PromotionSubscription { get; init; } = "promotion";

    /// <summary>Subscription consumed by the indexing worker.</summary>
    public string IndexingSubscription { get; init; } = "indexing";

    /// <summary>Subscription consumed by the notification worker.</summary>
    public string NotificationSubscription { get; init; } = "notification";
}

/// <summary>
/// Working-day service-level configuration.
/// </summary>
/// <remarks>Technical Architecture Document v1.3, Section 8.3.</remarks>
public sealed class SlaOptions
{
    /// <summary>Configuration section name.</summary>
    public const string SectionName = "Docaya:Sla";

    /// <summary>End-to-end target for Urgent, in working days.</summary>
    public int UrgentWorkingDays { get; init; } = 12;

    /// <summary>End-to-end target for Normal, in working days.</summary>
    public int NormalWorkingDays { get; init; } = 30;

    /// <summary>
    /// Warning window in working days. At risk is raised when remaining days fall inside
    /// this window - before the target date, not after it.
    /// </summary>
    public int WarningWindowWorkingDays { get; init; } = 3;
}
