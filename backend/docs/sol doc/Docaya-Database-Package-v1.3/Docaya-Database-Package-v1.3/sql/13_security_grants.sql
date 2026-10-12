/*==============================================================================
  13 · SECURITY GRANTS  ·  LEAST PRIVILEGE PER WORKLOAD
  Each workload receives ONLY the access it needs. There is no omnipotent
  account. A compromise of one worker cannot reach another schema.
  TAD 11.2 / 14.6.3
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*=========================== CAPTURE IDENTITY ===============================
  Granted on stg ONLY. Even if compromised it cannot read or alter the
  registry, workflow state, access policy or the audit chain.               */
GRANT SELECT, INSERT, UPDATE         ON SCHEMA::stg    TO docaya_capture_role;
GRANT SELECT                         ON SCHEMA::ref    TO docaya_capture_role;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::docaya TO docaya_capture_role;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::wf     TO docaya_capture_role;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::sec    TO docaya_capture_role;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::aud    TO docaya_capture_role;
DENY  SELECT, INSERT, UPDATE, DELETE ON SCHEMA::idx    TO docaya_capture_role;
GO

/*============================== API IDENTITY ================================
  Runtime application operations. INSERT + SELECT only on aud — never UPDATE
  or DELETE, which is what makes the hash chain defensible.                 */
GRANT SELECT, INSERT, UPDATE ON SCHEMA::docaya TO docaya_api_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::wf     TO docaya_api_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::ntf    TO docaya_api_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::ops    TO docaya_api_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::stg    TO docaya_api_role;
GRANT SELECT                 ON SCHEMA::ref    TO docaya_api_role;
GRANT SELECT                 ON SCHEMA::idx    TO docaya_api_role;
GRANT SELECT                 ON SCHEMA::rpt    TO docaya_api_role;
GRANT SELECT                 ON SCHEMA::sec    TO docaya_api_role;
GRANT INSERT                 ON sec.AccessDecisionLog TO docaya_api_role;
GRANT SELECT, INSERT         ON SCHEMA::aud    TO docaya_api_role;
DENY  UPDATE, DELETE         ON SCHEMA::aud    TO docaya_api_role;   -- append-only
DENY  DELETE                 ON SCHEMA::docaya TO docaya_api_role;   -- disposition only
DENY  INSERT, UPDATE, DELETE ON sec.AccessPolicy  TO docaya_api_role;
DENY  INSERT, UPDATE, DELETE ON sec.PolicyVersion TO docaya_api_role;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::ref       TO docaya_api_role;
GO

/*========================= WORKFLOW WORKER IDENTITY ========================*/
GRANT SELECT, INSERT, UPDATE ON SCHEMA::wf     TO docaya_worker_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::ops    TO docaya_worker_role;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::ntf    TO docaya_worker_role;
GRANT SELECT, UPDATE         ON SCHEMA::docaya TO docaya_worker_role;
GRANT SELECT, UPDATE         ON SCHEMA::stg    TO docaya_worker_role;
GRANT SELECT                 ON SCHEMA::ref    TO docaya_worker_role;
GRANT SELECT                 ON SCHEMA::sec    TO docaya_worker_role;
GRANT INSERT                 ON SCHEMA::aud    TO docaya_worker_role;
DENY  UPDATE, DELETE         ON SCHEMA::aud    TO docaya_worker_role;
DENY  INSERT, UPDATE, DELETE ON SCHEMA::sec    TO docaya_worker_role;
GO

/*========================= INDEXING WORKER IDENTITY =========================
  Read-only on the registry — it can never alter a document, only project it. */
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::idx    TO docaya_index_role;
GRANT SELECT                         ON SCHEMA::docaya TO docaya_index_role;
GRANT SELECT                         ON SCHEMA::ref    TO docaya_index_role;
GRANT SELECT                         ON SCHEMA::sec    TO docaya_index_role;
GRANT SELECT                         ON SCHEMA::stg    TO docaya_index_role;
GRANT SELECT, INSERT, UPDATE         ON SCHEMA::ops    TO docaya_index_role;
GRANT INSERT                         ON SCHEMA::aud    TO docaya_index_role;
DENY  UPDATE, DELETE                 ON SCHEMA::aud    TO docaya_index_role;
DENY  INSERT, UPDATE, DELETE         ON SCHEMA::docaya TO docaya_index_role;
DENY  INSERT, UPDATE, DELETE         ON SCHEMA::wf     TO docaya_index_role;
GO

/*============================ ANALYTICS IDENTITY ============================
  SELECT on rpt views ONLY — reporting cannot bypass the view shape.        */
GRANT SELECT ON SCHEMA::rpt    TO docaya_report_role;
DENY  SELECT ON SCHEMA::docaya TO docaya_report_role;
DENY  SELECT ON SCHEMA::stg    TO docaya_report_role;
DENY  SELECT ON SCHEMA::wf     TO docaya_report_role;
DENY  SELECT ON SCHEMA::sec    TO docaya_report_role;
DENY  SELECT ON SCHEMA::aud    TO docaya_report_role;
DENY  SELECT ON SCHEMA::ops    TO docaya_report_role;
DENY  SELECT ON SCHEMA::idx    TO docaya_report_role;
DENY  SELECT ON SCHEMA::ntf    TO docaya_report_role;
GO

/*============================ SUPPORT IDENTITY ==============================
  Technical status only. NEVER document content or business metadata.       */
GRANT SELECT ON SCHEMA::ops        TO docaya_support_role;
GRANT SELECT ON idx.IndexQueue     TO docaya_support_role;
GRANT SELECT ON idx.IndexReconcile TO docaya_support_role;
DENY  SELECT ON SCHEMA::docaya     TO docaya_support_role;
DENY  SELECT ON SCHEMA::stg        TO docaya_support_role;
DENY  SELECT ON SCHEMA::aud        TO docaya_support_role;
DENY  SELECT ON SCHEMA::sec        TO docaya_support_role;
DENY  SELECT ON SCHEMA::ntf        TO docaya_support_role;
DENY  SELECT ON SCHEMA::rpt        TO docaya_support_role;
GO

/*=========================== MIGRATION IDENTITY =============================
  DDL rights, used ONLY by the release pipeline, never at runtime.
  Deliberately NOT granted data-plane SELECT on document content.           */
GRANT ALTER, CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION
    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::docaya TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::stg    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::wf     TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::sec    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::ref    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::idx    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::ntf    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::aud    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::ops    TO docaya_migrate_role;
GRANT ALTER ON SCHEMA::rpt    TO docaya_migrate_role;
GO

/*======================== PROGRAMMABILITY EXECUTE ==========================*/
GRANT EXECUTE ON docaya.usp_IssueTrackingNumber   TO docaya_api_role;
GRANT EXECUTE ON aud.usp_AppendAuditEvent         TO docaya_api_role;
GRANT EXECUTE ON aud.usp_AppendAuditEvent         TO docaya_worker_role;
GRANT EXECUTE ON aud.usp_AppendAuditEvent         TO docaya_index_role;
GRANT EXECUTE ON wf.usp_ResolveRoute              TO docaya_api_role;
GRANT EXECUTE ON wf.usp_SweepSlaStatus            TO docaya_worker_role;
GRANT EXECUTE ON ops.usp_EnqueueOutbox            TO docaya_api_role;
GRANT EXECUTE ON ops.usp_EnqueueOutbox            TO docaya_worker_role;
GRANT EXECUTE ON docaya.usp_PurgeStagingArtifacts TO docaya_worker_role;
GRANT EXECUTE ON aud.usp_VerifyChain              TO docaya_worker_role;

GRANT EXECUTE ON ref.fn_IsWorkingDay       TO docaya_api_role;
GRANT EXECUTE ON ref.fn_AddWorkingDays     TO docaya_api_role;
GRANT EXECUTE ON ref.fn_WorkingDaysBetween TO docaya_api_role;
GRANT EXECUTE ON ref.fn_IsWorkingDay       TO docaya_worker_role;
GRANT EXECUTE ON ref.fn_AddWorkingDays     TO docaya_worker_role;
GRANT EXECUTE ON ref.fn_WorkingDaysBetween TO docaya_worker_role;
GO

/*======================= ROW-LEVEL SECURITY (rpt) ==========================
  Mirrors the Docaya department scope. The predicate reads SESSION_CONTEXT,
  which the Power BI embed-token service sets per user.                     */
IF SCHEMA_ID('rls') IS NULL EXEC('CREATE SCHEMA rls AUTHORIZATION dbo;');
GO

CREATE OR ALTER FUNCTION rls.fn_DepartmentPredicate (@DepartmentId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS fn_result
    WHERE
        /* Platform-wide reader (System Administrator, Records Officer, Auditor) */
        CAST(SESSION_CONTEXT(N'DocayaAllDepartments') AS BIT) = 1
        /* Or the viewer's own department scope */
     OR @DepartmentId = TRY_CAST(SESSION_CONTEXT(N'DocayaDepartmentId') AS INT)
        /* Or an explicitly granted cross-department list */
     OR EXISTS (
            SELECT 1
            FROM OPENJSON(CAST(SESSION_CONTEXT(N'DocayaDepartmentIds') AS NVARCHAR(MAX)))
            WHERE TRY_CAST(value AS INT) = @DepartmentId
        );
GO

/* Created with STATE = OFF. Enable during Phase 13 (Analytics) AFTER the
   embed-token service populates SESSION_CONTEXT, otherwise every report
   returns zero rows:
       ALTER SECURITY POLICY rls.DocayaDepartmentRls WITH (STATE = ON);      */
IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = 'DocayaDepartmentRls')
    CREATE SECURITY POLICY rls.DocayaDepartmentRls
        ADD FILTER PREDICATE rls.fn_DepartmentPredicate(DepartmentId) ON docaya.Document
        WITH (STATE = OFF);
GO

PRINT '13 · security grants applied (least privilege per workload).';
GO
