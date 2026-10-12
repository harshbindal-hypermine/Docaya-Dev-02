# Infrastructure tests

Technical Architecture Document v1.3, Section 18.5 — Validation, Drift and Rollback.

Two kinds of test live here, both blocking.

## Template unit tests — pull-request pipeline

Assert properties of the compiled template before anything is deployed:

| Assertion                                                | Why it is blocking                                                                                      |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Naming follows `{type}-docaya-{env}-{region}`.           | Every resource must be identifiable from its name alone (TAD 18.1).                                     |
| The mandatory tag set is present on every resource.      | `workload`, `environment`, `owner`, `costCentre`, `dataClassification`, `residency`, `releaseVersion`.  |
| Public network access is disabled on every data service. | Data services are private from the outset, not hardened afterwards (TAD 18.3).                          |
| TLS minimum version is enforced.                         | Zero-trust transport baseline (TAD 15.1).                                                               |
| The API image is a digest, never a floating tag.         | A floating tag in production is prohibited; the digest is what makes rollback deterministic (TAD 18.4). |

## Post-deploy assertions — release pipeline

Run against the deployed environment. Failure stops the release:

- Private-endpoint resolution and DNS resolve to private addresses.
- Managed identities exist and role assignments are scoped exactly as declared.
- The running workload can reach each dependency it needs on first start.

## Running

```powershell
pwsh -File infra/tests/validate-template.ps1
pwsh -File infra/tests/validate-deployment.ps1 -ResourceGroupName rg-docaya-dev-uaenorth -Environment dev
pwsh -File infra/scripts/what-if.ps1 -Environment dev
az bicep build --file infra/main.bicep --stdout
```

`validate-template.ps1` is the offline, blocking template-unit-test gate. It
compiles the full module graph and checks the resource estate, private task-hub
storage, immutable image addressing, Service Bus tier logic and removal of
orphan modules. It does not require an Azure subscription.

`validate-deployment.ps1` is the read-only post-deployment gate. It verifies the
required service estate exists and, for test and production, confirms that the
private-endpoint posture is present and every storage account has public network
access disabled.
