/*==============================================================================
  15 · POST-DEPLOYMENT VALIDATION
  Blocking assertions. Any FAIL row THROWs and stops the release (TAD 18.5).
==============================================================================*/
SET NOCOUNT ON;
GO

DECLARE @results TABLE (
    CheckNo   INT,
    CheckName NVARCHAR(120),
    Expected  NVARCHAR(80),
    Actual    NVARCHAR(80),
    Result    NVARCHAR(8)
);

/* 1 · All ten schemas exist */
INSERT INTO @results
SELECT 1, N'Schemas created', N'10', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 10 THEN N'PASS' ELSE N'FAIL' END
FROM sys.schemas
WHERE name IN (N'stg',N'docaya',N'wf',N'sec',N'ref',N'idx',N'ntf',N'aud',N'ops',N'rpt');

/* 2 · Core registry tables present */
INSERT INTO @results
SELECT 2, N'docaya tables', N'>= 8', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 8 THEN N'PASS' ELSE N'FAIL' END
FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'docaya';

/* 3 · Tracking number is UNIQUE */
INSERT INTO @results
SELECT 3, N'TrackingNumber unique constraint', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
WHERE t.name = N'Document' AND SCHEMA_NAME(t.schema_id) = N'docaya'
  AND i.is_unique = 1 AND i.name = N'UQ_Document_Tracking';

/* 4 · Promotion ledger idempotency key UNIQUE -> exactly-once publication */
INSERT INTO @results
SELECT 4, N'PromotionLedger idempotency UNIQUE', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.indexes i
JOIN sys.tables t ON t.object_id = i.object_id
WHERE t.name = N'PromotionLedger' AND SCHEMA_NAME(t.schema_id) = N'ops'
  AND i.is_unique = 1 AND i.name = N'UQ_PromotionLedger_Idempotency';

/* 5 · Audit immutability trigger exists */
INSERT INTO @results
SELECT 5, N'Audit append-only trigger', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.triggers WHERE name = N'TR_AuditEvent_Immutable';

/* 6 · No UPDATE or DELETE grant on aud for any application role */
INSERT INTO @results
SELECT 6, N'No UPDATE/DELETE grant on aud', N'0', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM sys.database_permissions p
JOIN sys.database_principals pr ON pr.principal_id = p.grantee_principal_id
WHERE p.class_desc = N'SCHEMA' AND SCHEMA_NAME(p.major_id) = N'aud'
  AND p.permission_name IN (N'UPDATE', N'DELETE')
  AND p.state_desc = N'GRANT' AND pr.name LIKE N'docaya[_]%';

/* 7 · Capture role is DENIED the registry */
INSERT INTO @results
SELECT 7, N'Capture role denied docaya schema', N'>= 1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.database_permissions p
JOIN sys.database_principals pr ON pr.principal_id = p.grantee_principal_id
WHERE p.class_desc = N'SCHEMA' AND SCHEMA_NAME(p.major_id) = N'docaya'
  AND p.state_desc = N'DENY' AND pr.name = N'docaya_capture_role';

/* 8 · Index record cannot hold a non-Published live row */
INSERT INTO @results
SELECT 8, N'Index published-only constraint', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.check_constraints WHERE name = N'CK_IdxRec_PublishedOnly';

/* 9 · Return requires a comment and a correction point */
INSERT INTO @results
SELECT 9, N'Mandatory return-comment constraint', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.check_constraints WHERE name = N'CK_Thread_ReturnComment';

/* 10 · Extension requires reason, actor and a new target */
INSERT INTO @results
SELECT 10, N'Mandatory extension-reason constraint', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.check_constraints WHERE name = N'CK_Sla_ExtensionReason';

/* 11 · 100 MB single-file cap enforced in the database */
INSERT INTO @results
SELECT 11, N'100 MB file-size constraints', N'>= 2', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 2 THEN N'PASS' ELSE N'FAIL' END
FROM sys.check_constraints
WHERE name IN (N'CK_Version_Size', N'CK_Staged_Size', N'CK_Session_Size');

/* 12 · One file per registration (single open upload session per document) */
INSERT INTO @results
SELECT 12, N'One open upload session per document', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.indexes WHERE name = N'UX_UploadSession_OpenPerDoc' AND is_unique = 1;

/* 13 · Exactly one owning department per document */
INSERT INTO @results
SELECT 13, N'Single owning Department Tag', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.indexes WHERE name = N'UX_DocumentTag_Owning' AND is_unique = 1;

/* 14 · Review chain restricted to 3 or 4 stages */
INSERT INTO @results
SELECT 14, N'Route stage-count constraint (3-4)', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.check_constraints WHERE name = N'CK_Route_Stages';

/* 15 · Notification de-duplication is enforced */
INSERT INTO @results
SELECT 15, N'Notification dedup unique index', N'1', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 1 THEN N'PASS' ELSE N'FAIL' END
FROM sys.indexes WHERE name = N'UX_Notification_Dedup' AND is_unique = 1;

/* 16-19 · Seed data present */
INSERT INTO @results
SELECT 16, N'Status catalogue seeded', N'12', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 12 THEN N'PASS' ELSE N'FAIL' END FROM ref.Status;
INSERT INTO @results
SELECT 17, N'Roles seeded', N'12', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 12 THEN N'PASS' ELSE N'FAIL' END FROM sec.Role;
INSERT INTO @results
SELECT 18, N'SLA targets seeded (12/30)', N'2', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 2 THEN N'PASS' ELSE N'FAIL' END
FROM ref.SlaTarget WHERE ScopeType = N'Global';
INSERT INTO @results
SELECT 19, N'Default 4-stage route seeded', N'4', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 4 THEN N'PASS' ELSE N'FAIL' END
FROM wf.RouteStage rs
JOIN wf.RouteDefinition rd ON rd.RouteDefinitionId = rs.RouteDefinitionId
WHERE rd.RouteCode = N'GLOBAL-4STAGE';

/* 20 · Reporting views created */
INSERT INTO @results
SELECT 20, N'Reporting views', N'>= 9', CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) >= 9 THEN N'PASS' ELSE N'FAIL' END
FROM sys.views WHERE SCHEMA_NAME(schema_id) = N'rpt';

/* 21 · Working-day arithmetic round trip (Urgent = 12 working days) */
BEGIN TRY
    DECLARE @target DATE = ref.fn_AddWorkingDays(N'UAE-FED', 1, '2026-09-01', 12);
    DECLARE @back   INT  = ref.fn_WorkingDaysBetween(N'UAE-FED', 1, '2026-09-01', @target);
    INSERT INTO @results
    SELECT 21, N'Working-day round trip (12 days)', N'12', CAST(@back AS NVARCHAR(80)),
           CASE WHEN @back = 12 THEN N'PASS' ELSE N'FAIL' END;
END TRY
BEGIN CATCH
    INSERT INTO @results VALUES (21, N'Working-day round trip (12 days)', N'12', ERROR_MESSAGE(), N'FAIL');
END CATCH

/* 22 · No cascade delete into a business schema */
INSERT INTO @results
SELECT 22, N'No cascade delete on registry/workflow/audit', N'0',
       CAST(COUNT(*) AS NVARCHAR(80)),
       CASE WHEN COUNT(*) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM sys.foreign_keys fk
JOIN sys.tables t ON t.object_id = fk.parent_object_id
WHERE fk.delete_referential_action_desc = N'CASCADE'
  AND SCHEMA_NAME(t.schema_id) IN (N'docaya', N'wf', N'aud', N'sec');

/*--------------------------------------------------------------- REPORT */
SELECT CheckNo, CheckName, Expected, Actual, Result
FROM @results ORDER BY CheckNo;

DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Result = N'FAIL');
IF @failed > 0
BEGIN
    DECLARE @msg NVARCHAR(200) =
        CONCAT(N'Docaya database validation FAILED: ', @failed, N' check(s) did not pass. Release blocked.');
    THROW 51100, @msg, 1;
END
PRINT '15 · all validation checks PASSED.';
GO
