namespace Docaya.Application.Ports;

/// <summary>
/// The outcome of an authorization evaluation.
/// </summary>
/// <param name="IsAllowed">Whether the action is permitted.</param>
/// <param name="PolicyVersion">
/// Version of the policy that produced the decision. Logged with every decision
/// (TAD 24.1).
/// </param>
/// <param name="DenyReason">Stable reason code when the decision is a denial.</param>
public readonly record struct AuthorizationDecision(
    bool IsAllowed,
    string PolicyVersion,
    string? DenyReason)
{
    /// <summary>Creates an allow decision.</summary>
    /// <param name="policyVersion">Version of the policy that allowed the action.</param>
    /// <returns>An allow decision.</returns>
    public static AuthorizationDecision Allow(string policyVersion) =>
        new(true, policyVersion, null);

    /// <summary>Creates a deny decision.</summary>
    /// <param name="policyVersion">Version of the policy that denied the action.</param>
    /// <param name="reason">Stable reason code.</param>
    /// <returns>A deny decision.</returns>
    public static AuthorizationDecision Deny(string policyVersion, string reason) =>
        new(false, policyVersion, reason);
}

/// <summary>
/// Evaluates the RBAC role gate and then the ABAC predicates for an action.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Sections 6.2, 14.4 and 14.5. Policy is applied
/// before any store is touched and the decision is deny by default. On denial the data
/// call is never issued and the decision is logged with the policy version.
/// </para>
/// </remarks>
public interface IAuthorizationPolicyEvaluator
{
    /// <summary>
    /// Evaluates whether a subject may perform an action on a resource.
    /// </summary>
    /// <param name="action">The action being attempted, for example <c>document.approve</c>.</param>
    /// <param name="resourceId">The resource identifier, when the action is resource-scoped.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The authorization decision.</returns>
    Task<AuthorizationDecision> EvaluateAsync(
        string action,
        Guid? resourceId,
        CancellationToken cancellationToken);

    /// <summary>
    /// Returns the caller's security keys, used to trim result sets before serialisation.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The caller's permission keys.</returns>
    Task<IReadOnlyCollection<string>> GetSecurityKeysAsync(CancellationToken cancellationToken);
}
