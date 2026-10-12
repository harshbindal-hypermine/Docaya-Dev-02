namespace Docaya.Infrastructure.Persistence;

/// <summary>
/// The database schema names.
/// </summary>
/// <remarks>
/// Technical Architecture Document v1.3, Section 11.2 - Schema Separation Strategy.
/// Separation is a control, not a naming convention: it lets least-privilege grants be
/// issued per schema and keeps staging, registry, workflow, security, reference, index
/// projection, notification, audit and operational concerns independently governable.
/// </remarks>
public static class DocayaSchemas
{
    /// <summary>Controlled staging zone. Holds the unchanged file until final approval.</summary>
    public const string Staging = "stg";

    /// <summary>Core document registry.</summary>
    public const string Registry = "docaya";

    /// <summary>Workflow, review chain, stage instances and SLA state.</summary>
    public const string Workflow = "wf";

    /// <summary>Access control: roles, attributes, policies and security keys.</summary>
    public const string Security = "sec";

    /// <summary>Reference data, including the versioned holiday calendar.</summary>
    public const string Reference = "ref";

    /// <summary>Index projection feeding Azure AI Search.</summary>
    public const string Index = "idx";

    /// <summary>Notification queue and delivery state.</summary>
    public const string Notification = "ntf";

    /// <summary>Hash-chained audit.</summary>
    public const string Audit = "aud";

    /// <summary>Operational state, including the promotion ledger and outbox.</summary>
    public const string Operations = "ops";

    /// <summary>All schema names, in the order they are created by migration.</summary>
    public static IReadOnlyList<string> All { get; } =
    [
        Staging,
        Registry,
        Workflow,
        Security,
        Reference,
        Index,
        Notification,
        Audit,
        Operations,
    ];
}
