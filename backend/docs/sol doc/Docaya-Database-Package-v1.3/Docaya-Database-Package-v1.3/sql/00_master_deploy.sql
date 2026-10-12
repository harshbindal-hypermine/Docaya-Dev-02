:On Error exit
/*==============================================================================
  DOCAYA EDMS  ·  MASTER DEPLOYMENT SCRIPT
  Version   : 1.3
  Target    : Azure SQL Database (compatible with SQL Server 2019+)
  Source    : Docaya Technical Architecture Document v1.3, Section 11
  Companion : Docaya-Database-Design-Document-v1.3.docx

  EXECUTION ORDER IS MANDATORY. Each script is idempotent and may be re-run.

    01_schemas_and_principals.sql   Schemas, database roles, workload users
    02_ref_reference_data.sql       ref  · catalogues and controlled vocabularies
    03_sec_access_control.sql       sec  · principals, RBAC, ABAC, policy, decisions
    04_docaya_core_registry.sql     docaya · document registry (system of record)
    05_stg_staging.sql              stg  · transient capture and staging
    06_wf_workflow_sla.sql          wf   · routes, stages, thread, SLA
    07_idx_index_projection.sql     idx  · search index projection state
    08_ntf_notification.sql         ntf  · notification history and preferences
    09_aud_audit.sql                aud  · append-only hash-chained audit
    10_ops_operational.sql          ops  · outbox, idempotency, promotion ledger
    11_rpt_reporting_views.sql      rpt  · read-only reporting views (RLS-ready)
    12_programmability.sql          Functions and stored procedures
    13_security_grants.sql          Least-privilege GRANT / DENY per workload
    14_seed_reference_data.sql      Seed catalogues and the working-day calendar
    15_validation_checks.sql        Post-deployment assertions (blocking)

  DESIGN RULES ENFORCED BY THESE SCRIPTS
    - Azure SQL is authoritative for all structured data.
    - stg is transient and purgeable; its principal has no access to docaya.
    - aud is append-only: no UPDATE or DELETE grant for any app principal.
    - idx, ntf and rpt are derived and rebuildable.
    - ops.PromotionLedger.IdempotencyKey is UNIQUE -> exactly-once publication.
    - No business table permits a cascade delete.
==============================================================================*/
SELECT
    DatabaseName   = DB_NAME(),
    ServerName     = @@SERVERNAME,
    EngineEdition  = SERVERPROPERTY('EngineEdition'),
    ProductVersion = SERVERPROPERTY('ProductVersion'),
    DeployStartUtc = SYSUTCDATETIME();
GO

:r "01_schemas_and_principals.sql"
:r "02_ref_reference_data.sql"
:r "03_sec_access_control.sql"
:r "04_docaya_core_registry.sql"
:r "05_stg_staging.sql"
:r "06_wf_workflow_sla.sql"
:r "07_idx_index_projection.sql"
:r "08_ntf_notification.sql"
:r "09_aud_audit.sql"
:r "10_ops_operational.sql"
:r "11_rpt_reporting_views.sql"
:r "12_programmability.sql"
:r "13_security_grants.sql"
:r "14_seed_reference_data.sql"
:r "15_validation_checks.sql"
