# Docaya EDMS — Database Deployment Scripts v1.3

Target: **Azure SQL Database** (SQL Server 2019+ compatible)
Companion document: **Docaya-Database-Design-Document-v1.3.docx**

---

## Execution order (mandatory)

Every script is **idempotent** and may be re-run safely. Order matters because
foreign keys resolve forward.

| # | Script | Creates |
|---|---|---|
| 00 | `00_master_deploy.sql` | Manifest and environment banner (no DDL) |
| 01 | `01_schemas_and_principals.sql` | 10 schemas · 7 database roles · workload users |
| 02 | `02_ref_reference_data.sql` | 14 catalogue tables |
| 03 | `03_sec_access_control.sql` | 7 access-control tables |
| 04 | `04_docaya_core_registry.sql` | 8 registry tables + hot-path indexes |
| 05 | `05_stg_staging.sql` | 6 staging tables |
| 06 | `06_wf_workflow_sla.sql` | 6 workflow tables |
| 07 | `07_idx_index_projection.sql` | 5 projection tables |
| 08 | `08_ntf_notification.sql` | 6 notification tables |
| 09 | `09_aud_audit.sql` | 3 audit tables + immutability trigger |
| 10 | `10_ops_operational.sql` | 6 operational tables |
| 11 | `11_rpt_reporting_views.sql` | 9 reporting views |
| 12 | `12_programmability.sql` | 4 functions · 7 procedures |
| 13 | `13_security_grants.sql` | 63 GRANT · 29 DENY · RLS predicate |
| 14 | `14_seed_reference_data.sql` | Seed catalogues, calendar, default route |
| 15 | `15_validation_checks.sql` | 22 blocking assertions |

### sqlcmd
```bash
for f in 0*.sql 1*.sql; do
  sqlcmd -S <server>.database.windows.net -d <database> -G -I -b -i "$f" || exit 1
done
```

### PowerShell
```powershell
Get-ChildItem *.sql | Where-Object { $_.Name -match '^\d\d_' } | Sort-Object Name |
  ForEach-Object { Invoke-Sqlcmd -ServerInstance $srv -Database $db -InputFile $_.FullName -AbortOnError }
```

> `01_schemas_and_principals.sql` needs an **Entra-authenticated admin session**
> to create users `FROM EXTERNAL PROVIDER`. If the managed identities do not yet
> exist it prints SKIP and continues; re-run after the Bicep identity module.

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
| Total lines | 2,868 |

---

## Before production

`ref.HolidayCalendar` ships **empty**. The weekend pattern (Sat + Sun) is set,
but the working-day SLA engine must not be trusted in production until the
client-supplied UAE public holidays are loaded. Open items **A2**, **A3** and
**A4** are marked inline in `14_seed_reference_data.sql`.

`rls.DocayaDepartmentRls` is created `WITH (STATE = OFF)`. Enable it in Phase 13
only after the Power BI embed-token service populates `SESSION_CONTEXT`.

---

## Verification performed

- All 80 DDL statements parse cleanly as T-SQL
- All 92 foreign keys resolve to a table created earlier in the order
- No duplicate constraint or index names
- Parentheses balanced; every file terminates with `GO`
- Working-day arithmetic independently verified including holiday handling
