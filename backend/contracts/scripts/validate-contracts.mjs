/**
 * Docaya contract validation.
 *
 * Enforces the API standards from Technical Architecture Document v1.3,
 * Section 24.1, and the domain event catalogue from Section 24.3, so that a
 * contract change that breaks an architectural rule fails the pull request
 * rather than a code review.
 *
 * Run:  npm run validate    (from src/contracts)
 */

import { readFile, readdir } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

import Ajv2020 from 'ajv/dist/2020.js'
import addFormats from 'ajv-formats'
import YAML from 'yaml'

const here = path.dirname(fileURLToPath(import.meta.url))
const contractsRoot = path.resolve(here, '..')

const OPENAPI_PATH = path.join(contractsRoot, 'openapi', 'docaya-api-v1.yaml')
const EVENTS_DIR = path.join(contractsRoot, 'events')

/** Single-file capture limit, TAD 7.1 step 1. */
const MAX_CAPTURE_BYTES = 104857600

/** Operations that are deliberately anonymous. Everything else must be secured. */
const ANONYMOUS_OPERATIONS = new Set(['getHealthLive', 'getHealthReady'])

/**
 * Query operations that use POST only to carry a request body. They do not
 * mutate state, so the idempotency rule in TAD 24.1 - which governs writes -
 * does not apply to them.
 */
const NON_MUTATING_POST_OPERATIONS = new Set(['search', 'ask'])

/** Methods that mutate state and therefore require an idempotency key (TAD 24.1). */
const WRITE_METHODS = new Set(['post', 'put', 'patch', 'delete'])

const HTTP_METHODS = new Set(['get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'])

/** Event catalogue from TAD 24.3. Every entry must have a schema file. */
const EVENT_CATALOGUE = [
  'DocumentRegistered',
  'DocumentSubmitted',
  'ReviewDecisionRecorded',
  'SlaRiskChanged',
  'SlaExtensionGranted',
  'FinalApprovalGranted',
  'DocumentPublished',
  'DocumentIndexed',
  'RevisionApproved',
  'AccessPolicyChanged',
  'RetentionActionDue',
]

const failures = []

function fail(message) {
  failures.push(message)
}

/** Converts PascalCase event name to the kebab-case schema file name. */
function schemaFileName(eventName) {
  return `${eventName.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase()}.schema.json`
}

// ---------------------------------------------------------------------------
// OpenAPI document
// ---------------------------------------------------------------------------

async function validateOpenApi() {
  const raw = await readFile(OPENAPI_PATH, 'utf8')

  let document
  try {
    document = YAML.parse(raw)
  } catch (error) {
    fail(`OpenAPI document is not valid YAML: ${error.message}`)
    return
  }

  if (typeof document.openapi !== 'string' || !document.openapi.startsWith('3.1')) {
    fail(`OpenAPI version must be 3.1.x, found "${document.openapi}" (TAD 24.1).`)
  }

  if (!document.components?.securitySchemes?.entraBearer) {
    fail('The entraBearer security scheme is missing (TAD 24.1 authentication).')
  }

  if (!Array.isArray(document.security) || !document.security.some((s) => 'entraBearer' in s)) {
    fail('A global entraBearer security requirement is missing; the API must be deny-by-default.')
  }

  for (const server of document.servers ?? []) {
    if (!server.url.includes('/api/v1')) {
      fail(`Server URL "${server.url}" must carry the /api/v1 major version (TAD 24.1 versioning).`)
    }
  }

  const operationIds = new Set()

  for (const [route, pathItem] of Object.entries(document.paths ?? {})) {
    for (const [method, operation] of Object.entries(pathItem)) {
      if (!HTTP_METHODS.has(method)) continue

      const label = `${method.toUpperCase()} ${route}`

      if (!operation.operationId) {
        fail(`${label} has no operationId; client generation requires one.`)
        continue
      }

      if (operationIds.has(operation.operationId)) {
        fail(`Duplicate operationId "${operation.operationId}" on ${label}.`)
      }
      operationIds.add(operation.operationId)

      const isAnonymous = ANONYMOUS_OPERATIONS.has(operation.operationId)
      const declaresAnonymous = Array.isArray(operation.security) && operation.security.length === 0

      if (isAnonymous && !declaresAnonymous) {
        fail(`${label} is a health probe and must declare "security: []".`)
      }
      if (!isAnonymous && declaresAnonymous) {
        fail(`${label} opts out of authentication but is not a health probe (deny by default, TAD 6.2).`)
      }

      if (
        WRITE_METHODS.has(method) &&
        !isAnonymous &&
        !NON_MUTATING_POST_OPERATIONS.has(operation.operationId)
      ) {
        const parameters = operation.parameters ?? []
        const hasIdempotencyKey = parameters.some(
          (parameter) =>
            parameter?.name === 'Idempotency-Key' ||
            parameter?.$ref === '#/components/parameters/IdempotencyKey',
        )
        if (!hasIdempotencyKey) {
          fail(`${label} is a write and must accept an Idempotency-Key (TAD 24.1 idempotency).`)
        }
      }

      for (const [status, response] of Object.entries(operation.responses ?? {})) {
        if (!/^[45]/.test(status)) continue
        const content = response.content ?? {}
        const isRef = typeof response.$ref === 'string'
        if (isRef) continue
        if (!content['application/problem+json']) {
          fail(`${label} response ${status} must use the application/problem+json envelope (TAD 6.3).`)
        }
      }

      if (!operation.responses || Object.keys(operation.responses).length === 0) {
        fail(`${label} declares no responses.`)
      }
    }
  }

  // Shared error responses must all use the problem-detail envelope.
  for (const [name, response] of Object.entries(document.components?.responses ?? {})) {
    if (!response.content?.['application/problem+json']) {
      fail(`Shared response "${name}" must use application/problem+json (TAD 6.3).`)
    }
  }

  const problemDetails = document.components?.schemas?.ProblemDetails
  if (!problemDetails) {
    fail('The ProblemDetails schema is missing; it is the single error envelope (TAD 6.3).')
  } else {
    for (const required of ['code', 'correlationId', 'status', 'title']) {
      if (!problemDetails.required?.includes(required)) {
        fail(`ProblemDetails must require "${required}" (TAD 6.3).`)
      }
    }
  }

  // The 100 MB single-file capture limit must be expressed in the contract.
  const stagedFileMax = document.components?.schemas?.StagedFile?.properties?.sizeBytes?.maximum
  if (stagedFileMax !== MAX_CAPTURE_BYTES) {
    fail(`StagedFile.sizeBytes.maximum must be ${MAX_CAPTURE_BYTES} (100 MB, TAD 7.1 step 1).`)
  }

  const uploadMax = document.components?.schemas?.UploadSession?.properties?.maxBytes?.const
  if (uploadMax !== MAX_CAPTURE_BYTES) {
    fail(`UploadSession.maxBytes.const must be ${MAX_CAPTURE_BYTES} (100 MB, TAD 7.1 step 1).`)
  }

  // The lifecycle states must match the domain state machine exactly.
  const statuses = document.components?.schemas?.DocumentStatus?.enum ?? []
  const expectedStatuses = [
    'PendingRegistration',
    'Classified',
    'PendingApproval',
    'InReview',
    'Returned',
    'Approved',
    'Published',
    'Superseded',
    'Expiring',
    'Archived',
    'Disposed',
  ]
  for (const status of expectedStatuses) {
    if (!statuses.includes(status)) {
      fail(`DocumentStatus is missing the "${status}" state (TAD 7.2).`)
    }
  }

  // A review route is three or four named stages - never fewer, never more.
  const routeStages = document.components?.schemas?.ReviewRoute?.properties?.stages
  if (routeStages?.minItems !== 3 || routeStages?.maxItems !== 4) {
    fail('ReviewRoute.stages must be constrained to 3..4 stages (TAD 8.1).')
  }

  // An Ask answer is always citation-bound.
  const citations = document.components?.schemas?.AskResponse?.properties?.citations
  if (citations?.minItems !== 1) {
    fail('AskResponse.citations must require at least one citation (TAD 10, grounding).')
  }
  if (!document.components?.schemas?.AskResponse?.required?.includes('citations')) {
    fail('AskResponse must require "citations"; answering is citation-bound (TAD 10).')
  }

  return document
}

// ---------------------------------------------------------------------------
// Domain event schemas
// ---------------------------------------------------------------------------

async function validateEvents() {
  const ajv = new Ajv2020({ strict: true, allErrors: true })
  addFormats(ajv)

  let entries
  try {
    entries = await readdir(EVENTS_DIR)
  } catch (error) {
    fail(`Unable to read the events directory: ${error.message}`)
    return
  }

  const schemaFiles = entries.filter((entry) => entry.endsWith('.schema.json'))

  for (const file of schemaFiles) {
    const raw = await readFile(path.join(EVENTS_DIR, file), 'utf8')
    let schema
    try {
      schema = JSON.parse(raw)
    } catch (error) {
      fail(`events/${file} is not valid JSON: ${error.message}`)
      continue
    }

    try {
      ajv.compile(schema)
    } catch (error) {
      fail(`events/${file} is not a valid JSON Schema: ${error.message}`)
      continue
    }

    if (!schema.title) fail(`events/${file} has no title.`)
    if (!schema.description) fail(`events/${file} has no description.`)
    if (schema.additionalProperties !== false && file !== 'envelope.schema.json') {
      fail(`events/${file} must set "additionalProperties": false so payloads stay closed.`)
    }
  }

  // The envelope drives dispatch; its eventType enum is the catalogue.
  const envelopeRaw = await readFile(path.join(EVENTS_DIR, 'envelope.schema.json'), 'utf8')
  const envelope = JSON.parse(envelopeRaw)
  const declared = envelope.properties?.eventType?.enum ?? []

  for (const eventName of EVENT_CATALOGUE) {
    if (!declared.includes(eventName)) {
      fail(`The envelope eventType enum is missing "${eventName}" (TAD 24.3).`)
    }
    const expectedFile = schemaFileName(eventName)
    if (!schemaFiles.includes(expectedFile)) {
      fail(`Event "${eventName}" has no schema file; expected events/${expectedFile} (TAD 24.3).`)
    }
  }

  for (const eventName of declared) {
    if (!EVENT_CATALOGUE.includes(eventName)) {
      fail(`The envelope declares "${eventName}", which is not in the TAD 24.3 catalogue.`)
    }
  }

  for (const required of ['eventId', 'eventType', 'occurredAtUtc', 'correlationId', 'idempotencyKey']) {
    if (!envelope.required?.includes(required)) {
      fail(`The event envelope must require "${required}" (TAD 24.3/24.4).`)
    }
  }

  return schemaFiles.length
}

// ---------------------------------------------------------------------------

const document = await validateOpenApi()
const eventSchemaCount = await validateEvents()

if (failures.length > 0) {
  console.error('Contract validation failed:\n')
  for (const failure of failures) console.error(`  - ${failure}`)
  console.error(`\n${failures.length} problem(s).`)
  process.exit(1)
}

const pathCount = Object.keys(document?.paths ?? {}).length
console.log('Contract validation passed.')
console.log(`  OpenAPI ${document.openapi}: ${pathCount} paths`)
console.log(`  Domain events: ${EVENT_CATALOGUE.length} catalogued, ${eventSchemaCount} schema files`)
