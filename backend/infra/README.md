# Docaya Infrastructure

Package 5 of 5. Technical Architecture Document v1.3, Sections 16, 18 and appendix A.

Bicep for the complete Docaya Azure estate, deployable into a **blank subscription**.
`main.bicep` is a subscription-scope composition root: it creates the resource group
and every resource inside it.

## Deploy

```powershell
az login
az account set --subscription <subscription-id>

# 1. Compile and lint.
az bicep build --file infra/main.bicep --stdout > $null

# 2. Preview. Reviewed and approved by a named person before any change (TAD 18.5).
pwsh -File infra/scripts/what-if.ps1 -Environment dev

# 3. Apply.
pwsh -File infra/scripts/deploy.ps1 -Environment dev -ApiImageDigest sha256:<digest>
```

> **Before the first deployment**, provide the required non-secret deployment
> values through environment variables. The parameter files do not contain fake
> defaults or tenant-specific identifiers. The SQL administrator must be an Entra
> **group** object ID, never an individual (TAD 14.8).

```powershell
$env:DOCAYA_COST_CENTRE = '<cost-centre>'
$env:DOCAYA_API_IMAGE_DIGEST = 'sha256:<64 lowercase hex characters>'
$env:DOCAYA_SQL_ADMIN_GROUP_OBJECT_ID = '<entra-group-object-id>'
$env:DOCAYA_ALERT_EMAIL_ADDRESS = '<on-call-address>'
$env:DOCAYA_APIM_PUBLISHER_EMAIL = '<publisher-address>'
```

Production additionally requires:

```powershell
$env:DOCAYA_ADMINISTRATIVE_IP_ALLOW_LIST = '["203.0.113.10/32"]'
$env:DOCAYA_NOTIFICATION_SENDER_DOMAIN = 'notifications.example.com'
```

The release script supplies `-ApiImageDigest` explicitly, overriding the
environment value during a deployment. Do not commit real tenant values,
addresses or document data to the parameter files.

## Layout

```
infra/
├─ main.bicep                 subscription-scope composition root
├─ bicepconfig.json           linter, 30 rules, errors on security-relevant ones
├─ environments/
│  ├─ dev.bicepparam          single zone · synthetic data · Ask on
│  ├─ test.bicepparam         zone-redundant · anonymised · private endpoints
│  └─ prod.bicepparam         geo-redundant · live · policy-enforced · Ask flagged off
├─ modules/
│  ├─ shared/types.bicep      CAF abbreviations, tags, role GUIDs, naming
│  ├─ network.bicep           VNet · 5 subnets · default-deny NSGs · 11 DNS zones
│  ├─ identity.bicep          6 user-assigned managed identities
│  ├─ observability.bicep     Log Analytics · App Insights · 4 alert rules
│  ├─ keyvault.bicep          RBAC data plane · purge protection · private endpoint
│  ├─ sql.bicep               Entra-only auth · TDE · auditing · LTR backup
│  ├─ storage.bicep           5 containers · lifecycle · versioning · no shared key
│  ├─ servicebus.bicep        topic · 5 filtered subscriptions · sessions · DLQ
│  ├─ search.bicep            RBAC-only · keys disabled · private endpoint
│  ├─ aiendpoint.bicep        embedding + answering · in-region · private
│  ├─ acr.bicep               Premium · admin disabled · retention · private
│  ├─ containerapp.bicep      internal ingress · image by digest · 3 probes
│  ├─ functions.bicep         EP plan · VNet integrated · identity-based storage
│  ├─ signalr.bicep           real-time push · local auth disabled
│  ├─ communication.bicep     email · residency-pinned · no engagement tracking
│  ├─ analytics.bicep         Power BI Embedded capacity
│  ├─ staticwebapp.bicep      web bundle hosting
│  ├─ apim.bicep              internal mode · token validation · rate limits
│  ├─ frontdoor.bicep         WAF OWASP 2.1 · bot rules · the only public surface
│  ├─ rbac.bicep              every data-plane grant, least privilege
│  └─ policy.bicep            13 assignments · deny in prod, audit below
├─ policy/                    additional policy assignments
├─ scripts/                   what-if · deploy · drift-detect
└─ tests/                     template unit tests · post-deploy assertions
```

## Naming and tagging

CAF abbreviations, `{type}-docaya-{env}-{region}` (TAD 18.1). Every resource is
identifiable from its name alone:

| Example                             | Resource                    |
| ----------------------------------- | --------------------------- |
| `rg-docaya-prod-uaenorth`           | Resource group              |
| `vnet-docaya-prod-uaenorth`         | Virtual network             |
| `sql-docaya-prod-uaenorth`          | SQL logical server          |
| `id-docaya-promotion-prod-uaenorth` | Promotion workload identity |

Where a name is length- or character-constrained — storage, Key Vault, registry,
Power BI — the pattern is compressed and the region moves to the tag set.

Mandatory tags on every resource: `workload`, `environment`, `owner`, `costCentre`,
`dataClassification`, `residency`, `releaseVersion`.

## Access control

Six workload identities, one per function, so a grant can be revoked from one
workload without affecting another (TAD 14.7):

| Identity    | Holds                                                                                                                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------- |
| `api`       | Blob **read** on staged + thumbnails · Search **Index Data Reader** · Service Bus Send · Key Vault Secrets User · AcrPull |
| `capture`   | Blob **write** on chunks, staged, thumbnails, quarantine · Service Bus Send                                               |
| `promotion` | Blob write on staged + quarantine + thumbnails · Service Bus **Receive on `promotion` only** · Graph `Sites.Selected`     |
| `indexing`  | Search **Index Data Contributor** · OpenAI User · Blob read on staged, write on extraction                                |
| `workflow`  | Durable task hub (blob/queue/table) · Service Bus Send + Receive on own subscriptions                                     |
| `analytics` | Key Vault Secrets User · `rpt` views only                                                                                 |

Three rules make this least privilege rather than a label:

1. **Blob grants are at container scope**, never account scope (TAD 14.6.2).
2. **Service Bus Receive is per subscription** — a worker cannot drain another's queue.
3. **Search reader/contributor are split** and API keys are disabled, so the separation
   cannot be bypassed by an admin key (TAD 12.5).

No connection string, account key, SAS or API key exists anywhere in these templates.
`disableLocalAuth` / `allowSharedKeyAccess: false` is set on Storage, Service Bus,
Search, OpenAI, SignalR and App Insights.

## Network — zero trust

One public surface. Everything else is private (TAD 16).

```
Internet → Front Door + WAF          ← the only public component
              ↓
         snet-edge   API Management (internal)
              ↓
         snet-app    Container Apps (internal ingress)
              ↓
         snet-pe     private endpoints → SQL · Blob · KV · Search · SB · OpenAI · ACR · SignalR
              ↑
         snet-func   Functions workers
         snet-mgmt   deployment + break-glass, control plane egress only
```

Every NSG denies by default at priority 4096 and opens only the flows in TAD 16.1.
`snet-pe` has **no permitted outbound** — private endpoints are destinations, never
initiators. Workload subnets have `Deny-Internet-Outbound`; egress to Microsoft 365 is
by service tag.

## Environment matrix (TAD 18.6)

|                     | dev       | test       | prod                             |
| ------------------- | --------- | ---------- | -------------------------------- |
| Zone redundant      | ✗         | ✓          | ✓                                |
| Private endpoints   | optional  | enabled    | **policy-enforced**              |
| Backup              | local     | local      | geo-redundant                    |
| Telemetry retention | 30 d      | 90 d       | 180 d                            |
| SQL PITR            | 7 d       | 14 d       | 35 d + LTR 7 y                   |
| Ask answering       | on        | on         | **off** — flagged on POC outcome |
| API replicas        | 1–3       | 2–10       | 3–30                             |
| WAF mode            | Detection | Prevention | Prevention                       |
| Policy effect       | Audit     | Audit      | **Deny**                         |

## What Bicep does not own

Deliberately, because they are data-plane or tenant objects that need a rehearsed
rollback (TAD 17.7):

- **SQL schemas and contained database principals** (`docaya_api`, `docaya_capture`,
  `docaya_worker`, `docaya_index`, `docaya_report`, `docaya_migrate`) — created by the
  migration bundle in `docs/sol doc/Docaya-Database-Package-v1.3/`.
- **Azure AI Search index schema** — created by the indexing worker at release time.
- **Entra app registrations, consent and `Sites.Selected` grants** — tenant objects,
  created by `deploy/scripts/tenant-bootstrap.ps1`.
- **Power BI workspace, semantic model and RLS roles** — created against the Power BI
  REST API.

## Validation

```powershell
az bicep build --file infra/main.bicep --stdout > $null    # compile + 30 lint rules
pwsh -File infra/scripts/what-if.ps1     -Environment dev  # preview
pwsh -File infra/scripts/drift-detect.ps1 -Environment prod # scheduled drift check
```

The linter treats security-relevant rules as **errors**, not warnings —
`outputs-should-not-contain-secrets`, `secure-parameter-default`,
`use-secure-value-for-secure-inputs`, `no-hardcoded-env-urls`.

### Additional environment inputs

Test and production require `DOCAYA_ADMINISTRATIVE_IP_ALLOW_LIST` as a non-empty JSON array of approved CIDRs. Production also requires `DOCAYA_POWERBI_CAPACITY_ADMINISTRATORS` as a non-empty JSON array of capacity administrators. These values must come from the client.

The API receives its Entra authority and audience from the composition root. Its ingress is reachable inside the private VNet and its domain has a linked private DNS zone. API Management remains internal. Front Door-to-private-API routing still requires the approved private ingress design; successful compilation is not deployment approval.
