# Deployment scripts

**Current status: preparation only; complete implementation is BLOCKED.** See
[the readiness review](READINESS.md) and [the blocker register](readiness-blockers.json).
All new install, upgrade, rollback, database and tenant scripts default to a local
JSON plan. No deployment was executed while preparing them. Live paths still need
isolated rehearsal; the current package fails the execution gate.

Technical Architecture Document v1.3, Section 17.3 and Sections 20 to 23.

Docaya is a portable product, not a single-environment installation. These scripts
are what a client team runs to install it into an unrelated Microsoft tenant, and
what an operations team runs to upgrade, roll back or verify it.

| Script                         | Purpose                                                                                                                                | Source         |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `scripts/install.ps1`          | First-time installation into a target tenant.                                                                                          | TAD 20.3       |
| `scripts/upgrade.ps1`          | In-place upgrade to a newer release package.                                                                                           | TAD 20         |
| `scripts/rollback.ps1`         | Re-deploy the previous template version and re-point the API to the previous image digest.                                             | TAD 18.5       |
| `scripts/validate.ps1`         | Post-deploy assertions. Failure stops the release.                                                                                     | TAD 18.5       |
| `scripts/tenant-bootstrap.ps1` | Explicit SharePoint `Sites.Selected` grants for an existing promotion managed identity. App registration/federation remains a blocker. | TAD 20.3, 13.2 |

Additional local preparation tools:

| Script                         | Purpose                                                                                                                             |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/check-readiness.mjs`  | Source gap inspection and machine-readable blocker report; exits 1 while blocked.                                                   |
| `scripts/prepare-release.ps1`  | Assemble source-review package, or build a candidate with web/Functions/compiled ARM artifacts and SHA-256 manifest. Never deploys. |
| `scripts/build-api-image.ps1`  | Build and save an API container locally. Never pushes it.                                                                           |
| `scripts/migrate-database.ps1` | Plan or run canonical SQL master/versioned migration, using Entra authentication and SQLCMD identity variables.                     |
| `scripts/new-plan.ps1`         | Produce the ordered install/upgrade/rollback plan without accessing Azure.                                                          |
| `tests/scripts.tests.ps1`      | Offline regression tests with external commands replaced by local mocks.                                                            |

## Local preparation

Run from the repository root, using Windows PowerShell 5.1 or PowerShell 7:

```powershell
npm run release:readiness
& ./deploy/tests/scripts.tests.ps1
& ./deploy/scripts/prepare-release.ps1 -OutputDirectory artifacts/release-review -SourceOnly
& ./deploy/scripts/install.ps1 -ConfigurationFile deploy/config/environment.example.json -ReleaseDirectory artifacts/release-review
& ./deploy/scripts/upgrade.ps1 -ConfigurationFile deploy/config/environment.example.json -ReleaseDirectory artifacts/release-review
& ./deploy/scripts/rollback.ps1 -ConfigurationFile deploy/config/environment.example.json -ReleaseDirectory artifacts/release-review
& ./deploy/scripts/tenant-bootstrap.ps1 -ConfigurationFile deploy/config/environment.example.json
```

Use a fresh output directory for each preparation run. A source-only package is
always `BLOCKED`, includes no certified release binaries, and cannot be executed.
It includes a snapshot of application sources, templates, contracts, canonical SQL,
deployment scripts, readiness findings and file checksums. Local dependencies
(`npm ci`) are required for the source inspection.

For a full local candidate build, omit `-SourceOnly` and supply
`-ApiImageDigest sha256:<64-lowercase-hex-digits>` for the separately built and
scanned API image. This runs web/API/Functions tests and template validation,
publishes Functions, compiles ARM, and copies the web build. It remains `BLOCKED`
until the source/readiness gates pass. The image build helper requires Docker;
backend compilation requires the SDK pinned in `global.json`.

Checksums detect changes; they are not release signatures. Signing, SBOM/provenance
and scanning evidence are required before the release blocker can be resolved.

## Target inputs and future execution

Copy `config/environment.example.json` and `infra/main.parameters.example.json`
to private local configuration files. Use an absolute path for `parameterFile`.
Fill real tenant/subscription IDs, API registration ID, target resource names,
image digest, URLs, target parameters and six SQL identity names from Bicep outputs.
Keep deployment configuration outside a release package; do not commit client data
or credentials. Set `apiAudience` to the audience actually emitted by the approved
Entra token configuration. Do not use the example files directly for execution.

The install/upgrade/rollback scripts require explicit `-Execute` before any
external change. They check release status and hashes before invoking Azure,
require target-account alignment and a reviewed what-if evidence file, and check
the configured image digest against the selected release. No `-Execute` command
was run during preparation.

The current runner assumes a prepared target landing zone with the image already
in its ACR. **Blank-subscription install is still blocked by the template's ACR/API
ordering.** It also requires a private-network runner, existing approved Entra
registration/federation, Search schema, Power BI configuration and tenant setup.
It does not create these missing application components.

Installation runs `00_master_deploy.sql` once; that file includes scripts 01–15.
Never also iterate over all child scripts. The runner supplies `ApiIdentity`,
`CaptureIdentity`, `PromotionIdentity`, `WorkflowIdentity`, `IndexingIdentity` and
`AnalyticsIdentity` as SQLCMD variables. Upgrade accepts an explicit `-MigrationFile`;
without one it is an application-only upgrade and requires compatible schema.

Rollback uses the previous package and its matching configuration/parameter file.
Set `rollbackCompatibleDatabase` only after verifying backward compatibility.
No SQL down-migration or automatic data restore is attempted. The script redeploys
previous ARM, Functions and web artifacts; it is not a zero-downtime rollback guarantee.

`validate.ps1` checks local package integrity by default; `-Online` adds read-only
Azure resource and HTTP checks. `apiBaseUrl` must be an approved URL on the private
runner from which `/health/live` and `/health/ready` are actually exposed. Passing
these probes is not a substitute for a synthetic authenticated lifecycle test.

Command references: [Functions ZIP deployment](https://learn.microsoft.com/en-us/azure/azure-functions/deployment-zip-push),
[SWA deployment](https://azure.github.io/static-web-apps-cli/docs/cli/swa-deploy/),
[Graph site grants](https://learn.microsoft.com/en-us/graph/api/site-post-permissions?view=graph-rest-1.0),
[Graph application-role assignment](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-approleassignments?view=graph-rest-1.0).

## Cross-tenant principles

The release package carries no tenant identifier, no secret and no client data. Every
tenant-specific value is supplied at install time and stored in that tenant's Key
Vault (TAD 20.1).

## Rollback is rehearsed

Rollback is not a contingency plan written down once. It is rehearsed each release
(TAD 18.5), and a migration may not run against a shared environment until its
rollback has been rehearsed (TAD 17.7).
