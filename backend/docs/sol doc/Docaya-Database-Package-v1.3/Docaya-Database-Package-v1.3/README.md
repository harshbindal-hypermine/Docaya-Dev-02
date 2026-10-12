# Docaya EDMS — Database Package v1.3

Complete Azure SQL database deliverable: deployment scripts, design document
and installation guide.

---

## Contents

```
Docaya-Database-Package-v1.3/
├── README.md                                    ← this file
├── Docaya-Database-Design-Document-v1.3.docx    ← schema design (33 pages)
├── Docaya-Azure-SQL-Deployment-Guide-v1.3.docx  ← installation runbook (23 pages)
└── sql/
    ├── 00_master_deploy.sql            Manifest and environment banner
    ├── 01_schemas_and_principals.sql   10 schemas · 7 roles · workload users
    ├── 02_ref_reference_data.sql       14 catalogue tables
    ├── 03_sec_access_control.sql       7 access-control tables
    ├── 04_docaya_core_registry.sql     8 registry tables + hot-path indexes
    ├── 05_stg_staging.sql              6 staging tables
    ├── 06_wf_workflow_sla.sql          6 workflow tables
    ├── 07_idx_index_projection.sql     5 projection tables
    ├── 08_ntf_notification.sql         6 notification tables
    ├── 09_aud_audit.sql                3 audit tables + immutability trigger
    ├── 10_ops_operational.sql          6 operational tables
    ├── 11_rpt_reporting_views.sql      9 reporting views
    ├── 12_programmability.sql          4 functions · 7 procedures
    ├── 13_security_grants.sql          63 GRANT · 29 DENY · RLS predicate
    ├── 14_seed_reference_data.sql      Seed catalogues, calendar, default route
    └── 15_validation_checks.sql        22 blocking assertions
```

---

## Which document to read

| You are | Read |
|---|---|
| Deploying the database | **Azure SQL Deployment Guide** — provisioning, identity, execution, validation, rollback |
| Designing against the schema | **Database Design Document** — schemas, entity model, constraints, indexes |
| Reviewing security | Design Document §8 and Deployment Guide §7 |
| Reviewing compliance / audit | Design Document §6.3 (hash chain) and §12 (traceability) |

---

## Quick start

```bash
# sqlcmd — -G Entra auth, -b stop on error
SERVER='sql-docaya-<env>-<region>.database.windows.net'
DATABASE='docaya'

cd sql
for f in $(ls [0-1][0-9]_*.sql | sort); do
  echo "==> $f"
  sqlcmd -S "$SERVER" -d "$DATABASE" -G -I -b -i "$f" || { echo "FAILED at $f"; exit 1; }
done
```

```powershell
$srv = 'sql-docaya-<env>-<region>.database.windows.net'
$db  = 'docaya'
$tok = (Get-AzAccessToken -ResourceUrl 'https://database.windows.net').Token

Get-ChildItem sql\*.sql | Where-Object { $_.Name -match '^\d\d_' } | Sort-Object Name |
  ForEach-Object {
      Write-Host "==> $($_.Name)"
      Invoke-Sqlcmd -ServerInstance $srv -Database $db -AccessToken $tok `
                    -InputFile $_.FullName -AbortOnError
  }
```

> **Script 01 needs an Entra-authenticated admin session** to create users
> `FROM EXTERNAL PROVIDER`. If the managed identities do not yet exist it prints
> SKIP and continues; re-run it after the Bicep identity module completes.

---

## Object inventory

| | Count |
|---|---|
| Schemas | 10 |
| Tables | 63 |
| Foreign keys | 92 |
| Check constraints | 68 |
| Explicit indexes | 58 |
| Views | 9 |
| Stored procedures | 7 |
| Functions | 4 |
| Triggers | 1 |
| GRANT / DENY | 63 / 29 |
| Total SQL lines | 2,869 |

---

## Schema map

| Schema | Role | Classification |
|---|---|---|
| `stg` | Staging, upload, scan, extraction, thumbnail | **Transient** — purgeable |
| `docaya` | Document registry | **Authoritative** — system of record |
| `wf` | Routes, instances, stages, thread, SLA | **Authoritative** |
| `sec` | Principals, RBAC, ABAC, policy, decisions | **Authoritative** |
| `ref` | Catalogues and controlled vocabularies | **Configured** |
| `idx` | Search index projection state | **Derived** — rebuildable |
| `ntf` | Notification history and preferences | **Prunable** |
| `aud` | Append-only hash-chained audit | **Authoritative** |
| `ops` | Outbox, idempotency, promotion ledger | **Prunable** |
| `rpt` | Read-only reporting views (RLS-ready) | **Derived** |

---

## Architectural guarantees enforced in the database

| Guarantee | Mechanism |
|---|---|
| Exactly-once publication | `UQ_PromotionLedger_Idempotency` |
| Hash verified before publish | `CK_Promo_SuccessNeedsHash` |
| Audit append-only | `DENY UPDATE, DELETE` **plus** `TR_AuditEvent_Immutable` |
| No unapproved content in the index | `CK_IdxRec_PublishedOnly` |
| Return requires comment + correction point | `CK_Thread_ReturnComment` |
| Extension requires reason, actor, new target | `CK_Sla_ExtensionReason` |
| Original SLA target never overwritten | Separate columns + `CK_WfInst_Target` |
| One file per registration, max 100 MB | `UX_UploadSession_OpenPerDoc` + 3 size checks |
| Exactly one owning department | `UX_DocumentTag_Owning` |
| Review chain is 3 or 4 stages | `CK_Route_Stages` |
| One alert per recipient per event | `UX_Notification_Dedup` |
| Capture worker cannot read the registry | `DENY … ON SCHEMA::docaya TO docaya_capture_role` |
| Reporting cannot bypass the view shape | `DENY SELECT` on every base schema |
| No cascade delete into business data | Validated by check 22 |

---

## Before production

Two items **must** be closed:

1. **Load `ref.HolidayCalendar`** with client-confirmed UAE public holidays.
   It ships empty by design. The weekend pattern (Sat + Sun) is seeded, but the
   working-day SLA engine will compute 12/30-day targets as if no public
   holidays exist until this table is populated. *(Open item A4)*

2. **Enable row-level security** only after the Power BI embed-token service is
   confirmed to populate `SESSION_CONTEXT`:
   ```sql
   ALTER SECURITY POLICY rls.DocayaDepartmentRls WITH (STATE = ON);
   ```
   Enabling it prematurely makes every report return zero rows.

Also requiring client confirmation: document classes, departments and Standard
taxonomy (**A2**), retention schedules (**A2**), SLA targets and stage variants
(**A3**), customer-managed keys (**A9**). Each is marked inline in
`14_seed_reference_data.sql`.

---

## Verification performed on these scripts

- All 80 DDL statements parse cleanly as T-SQL
- All 92 foreign keys resolve to a table created earlier in the execution order
- No duplicate constraint or index names across the set
- Parentheses balanced in every file; every file terminates with `GO`
- Working-day arithmetic independently verified, including holiday handling
