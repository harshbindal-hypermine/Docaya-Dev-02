# Azure Policy assignments

Technical Architecture Document v1.3, Section 18.1.

Policy is a guardrail applied once the estate is complete (provisioning step 10,
TAD 18.3). These assignments are deployed with the infrastructure, not configured
by hand in the portal.

| Policy                                           | Effect                                                                                                             |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| Deny public network access on data services.     | SQL, Storage, Service Bus, Search, Key Vault and the AI endpoint must be reachable only through private endpoints. |
| Deny resource creation outside approved regions. | Data residency is pinned; the paired region is used only for backup and recovery, never live processing.           |
| Require the mandatory tag set.                   | `workload`, `environment`, `owner`, `costCentre`, `dataClassification`, `residency`, `releaseVersion`.             |
| Enforce private endpoints in production.         | Optional in dev, enabled in test, enforced by policy in production (TAD 18.6).                                     |

Add one `.bicep` file per assignment and reference it from `infra/main.bicep`.
