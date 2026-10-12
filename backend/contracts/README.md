# Docaya Contracts

Package 4 of 5. Technical Architecture Document v1.3, Section 17.1.

The contract precedes the code so the UI and API cannot drift (TAD 17.3). Nothing
in `src/web` or `src/api` may define its own wire shape — both consume what is
generated from here.

## Contents

| Path                             | Purpose                                              |
| -------------------------------- | ---------------------------------------------------- |
| `openapi/docaya-api-v1.yaml`     | OpenAPI 3.1 document for `/api/v1` (TAD 24.1, 24.2). |
| `events/envelope.schema.json`    | Common domain event envelope (TAD 24.3, 24.4).       |
| `events/*.schema.json`           | One schema per catalogued domain event.              |
| `scripts/validate-contracts.mjs` | Enforces the architecture rules on every change.     |
| `scripts/generate-clients.mjs`   | Generates the TypeScript and C# clients.             |

## Commands

```powershell
npm ci

# Fails the build when a contract change breaks an architecture rule.
npm run validate

# Generate both clients.
npm run gen

# Or individually.
npm run gen:ts    # -> src/web/src/api/generated
npm run gen:cs    # -> src/api/Generated   (requires: dotnet tool restore, in src/api)
```

## Rules enforced by `npm run validate`

These are not style preferences. Each one is a binding statement from the
architecture baseline, checked mechanically so it cannot regress silently.

| Rule                                                                             | Source            |
| -------------------------------------------------------------------------------- | ----------------- |
| Document is OpenAPI 3.1.x.                                                       | TAD 24.1          |
| `entraBearer` scheme exists and is applied globally; the API is deny-by-default. | TAD 24.1, 6.2     |
| Every server URL carries the `/api/v1` major version.                            | TAD 24.1          |
| Every operation has a unique `operationId`.                                      | Client generation |
| Only the two health probes may declare `security: []`.                           | TAD 6.2           |
| Every write operation accepts an `Idempotency-Key`.                              | TAD 24.1          |
| Every 4xx/5xx response uses `application/problem+json`.                          | TAD 6.3           |
| `ProblemDetails` requires `code`, `correlationId`, `status`, `title`.            | TAD 6.3           |
| The single-file capture limit is exactly 100 MB in both upload schemas.          | TAD 7.1           |
| `DocumentStatus` matches the domain state machine exactly.                       | TAD 7.2           |
| A review route is constrained to three or four stages.                           | TAD 8.1           |
| `AskResponse` requires at least one citation.                                    | TAD 10            |
| Every catalogued event has a closed schema and appears in the envelope enum.     | TAD 24.3          |

## Generated output is not committed

`src/web/src/api/generated/` and `src/api/Generated/` are git-ignored. Regenerate
them after any contract change; never edit them by hand.

## Changing the contract

Additive change only within `v1`. A breaking change requires a new major version
and an overlap period (TAD 24.1). Contract tests run on every OpenAPI and event
change (TAD 17.4).
