# Implementation readiness review

Reviewed locally on 27 September 2026 against the repository and the Technical Architecture Document v1.3. **The complete application and final deployment are not ready.** The new deployment scripts are prepared for review and offline testing; their live execution paths have not been rehearsed. No cloud resources, tenant objects, databases or deployed applications were changed.

## What is present and what remains

| Area                        | Evidence                                                                                                                | Readiness                                                                                                                                                                               |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contracts                   | 17 paths, 18 operations, 11 catalogued events; local contract validator passes                                          | Contract foundation present. API implementation is incomplete.                                                                                                                          |
| API                         | `src/api/Docaya.Api/Program.cs` maps health endpoints only                                                              | 16 contract business operations missing.                                                                                                                                                |
| Application and persistence | Application registration contains no use cases; DbContext has no concrete entity configurations in the inspected source | Implement business use cases, mappings, persisted state and transaction boundaries.                                                                                                     |
| Provider integration        | Eight declared ports have no concrete infrastructure implementation                                                     | Audit, authorization, promotion, outbox, idempotency, Search, staging and unit-of-work adapters missing.                                                                                |
| Workers                     | Six explicit `NotImplementedException` sites                                                                            | Promotion, verification, reconciliation, indexing, event handling and SLA evaluation incomplete. Other required capture/notification/retention/outbox workers also need implementation. |
| Browser application         | `main.tsx` starts `prototype/PrototypeApp`; state is stored in localStorage                                             | Demonstration UI, not the connected production application. Entra, server authorization and persisted workflows remain.                                                                 |
| Infrastructure              | Template validation passes with 157 compiled resource nodes                                                             | Compilation does not establish successful deployment. Private API ingress, first-image bootstrap and workload identity behavior remain unresolved.                                      |
| Database                    | Canonical SQL package includes master plus scripts 01–15                                                                | Local runner now supplies six SQLCMD managed-identity variables and runs only the master. No SQL execution/rehearsal performed.                                                         |
| Release automation          | Existing `release.yml` validates/previews only                                                                          | New local preparation/orchestration scripts provided. Signing, provenance, upgrade/rollback rehearsal and live pipeline integration remain.                                             |
| Tenant setup                | New helper prepares/applies explicit Sites.Selected grants for an existing identity                                     | API/SPA registration, scopes, app roles, national federation and broader tenant onboarding remain incomplete.                                                                           |
| Operations                  | Existing architecture/runbook text still refers to Node, PostgreSQL and Redis                                           | Must be reconciled with the authoritative .NET/Azure SQL architecture and recovery procedures.                                                                                          |

The current API contract itself does not cover every M1–M16 business feature. Matching its 18 operations is necessary, but is not proof of complete business coverage. The source scanner is a gap detector, not semantic verification: endpoint names, class declarations and resolved checklist entries cannot replace integration/security tests.

## Checks performed

- Contract validation: passed.
- Frontend ESLint: passed.
- Frontend unit/integration tests: 28 passed in seven files.
- TypeScript and Vite production build: passed.
- Bicep compilation and repository template assertions: passed, 157 compiled resource nodes.
- Deployment-script offline assertions: 33 passed, including blocked-release rejection, checksum validation, target-account checks, SQLCMD variable handling and native-command failure propagation.
- Backend and Functions tests: blocked before execution. `global.json` requires SDK 10.0.401; only SDK 8.0.425 is installed on this machine.
- Live Azure validation/what-if, SQL execution, tenant changes, image publishing and live release/rollback: not run.

Browser E2E verification is **not passed**. The full run found an ambiguous heading selector in `tests/e2e/docaya.spec.ts`; it was corrected to use an exact match, and the full run was stopped to isolate it. The targeted rerun reported one passing test but exited with suite/teardown timeout errors at the 60-second global limit. Browser-runner completion still needs investigation. These tests exercise the prototype and cannot establish production integration readiness.

## Prepared files

The [deployment guide](README.md) documents every script, its inputs and the local-only commands. [readiness-blockers.json](readiness-blockers.json) records the remaining implementation and verification work. `npm run release:readiness` produces a machine-readable report and exits nonzero while blockers remain.

`infra/main.parameters.example.json` previously targeted the obsolete PostgreSQL deployment. It now uses the current v1.3 Bicep parameters with intentionally empty client values. It is an example, not a deployable client configuration.

## Required completion order

1. Complete contract coverage, backend use cases, entities, authorization, audit and transactional outbox.
2. Implement the external adapters and worker pipelines, with negative authorization, replay, hash-integrity and failure-recovery tests.
3. Connect the production frontend to Entra and the generated contract client; separate the demo entry point explicitly.
4. Resolve private ingress, blank-subscription/ACR bootstrap, identity selection, Search provisioning and Power BI setup against the approved design.
5. Supply client identity/configuration, taxonomy, holidays, retention and reporting RLS; rehearse database install and versioned upgrades.
6. Produce, scan and sign immutable release artifacts, run connected system/security/performance tests, and rehearse installation, rollback and restore in an isolated target.
7. Resolve each blocker with a repository-local verification artifact and obtain the release approvals required by the baseline. Only then can the complete release be confirmed ready.

This preparation deliberately does not substitute mock backend implementations for missing production behavior.
