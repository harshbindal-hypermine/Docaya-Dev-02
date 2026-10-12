/*==============================================================================
  11 · rpt  ·  REPORTING VIEWS  (READ-ONLY · SHAPED FOR POWER BI + RLS)
  The Power BI semantic model reads ONLY these views. Row-level security
  predicates mirror the Docaya department and sensitivity scope.  TAD 25.2
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

CREATE OR ALTER VIEW rpt.vwDocumentRegistry AS
SELECT
    d.DocumentId, d.TrackingNumber, d.BusinessTitle, d.StatusCode,
    s.DisplayNameEn AS StatusName, s.IsPublished,
    c.ClassCode, c.DisplayNameEn AS DocumentClass,
    sv.SensitivityCode, sv.DisplayNameEn AS Sensitivity, sv.ClearanceRank,
    dep.DepartmentId, dep.DepartmentCode, dep.DisplayNameEn AS OwningDepartment,
    std.StandardCode, std.DisplayNameEn AS Standard,
    ps.ScopeCode AS PublishingScope, pr.PriorityCode, pr.RequestType,
    d.OwnerPrincipalId, o.DisplayName AS OwnerName,
    d.LegalHoldFlag, d.ExpiryUtc, d.DispositionDueUtc, d.CreatedUtc, d.ModifiedUtc,
    v.VersionLabel AS CurrentVersionLabel, v.PublishedUtc AS CurrentVersionPublishedUtc,
    CASE WHEN d.ExpiryUtc IS NOT NULL
          AND d.ExpiryUtc <= DATEADD(DAY, 30, CAST(SYSUTCDATETIME() AS DATE))
         THEN 1 ELSE 0 END AS IsExpiringSoon,
    DATEDIFF(DAY, d.ModifiedUtc, SYSUTCDATETIME()) AS DaysSinceLastChange
FROM docaya.Document d
JOIN ref.Status          s   ON s.StatusCode     = d.StatusCode
JOIN ref.DocumentClass   c   ON c.ClassId        = d.ClassId
JOIN ref.Sensitivity     sv  ON sv.SensitivityId = d.SensitivityId
JOIN ref.Department      dep ON dep.DepartmentId = d.DepartmentId
JOIN ref.PublishingScope ps  ON ps.ScopeId       = d.PublishingScopeId
JOIN ref.Priority        pr  ON pr.PriorityId    = d.PriorityId
JOIN sec.Principal       o   ON o.PrincipalId    = d.OwnerPrincipalId
LEFT JOIN ref.Standard   std ON std.StandardId   = d.StandardId
LEFT JOIN docaya.DocumentVersion v ON v.VersionId = d.CurrentVersionId;
GO

CREATE OR ALTER VIEW rpt.vwWorkflowPerformance AS
SELECT
    wi.WorkflowInstanceId, wi.DocumentId, d.TrackingNumber,
    d.DepartmentId, dep.DisplayNameEn AS DepartmentName, c.ClassCode,
    wi.InstanceType, wi.RequestType, wi.StateCode,
    wi.StartedUtc, wi.CompletedUtc, wi.OriginalTargetUtc, wi.CurrentTargetUtc,
    DATEDIFF(DAY, wi.OriginalTargetUtc, wi.CurrentTargetUtc) AS ExtensionDaysGranted,
    wi.IsAtRisk, wi.IsOverdue,
    CASE WHEN wi.CompletedUtc IS NULL THEN NULL
         WHEN CAST(wi.CompletedUtc AS DATE) <= wi.OriginalTargetUtc THEN 1 ELSE 0
    END AS MetOriginalTarget,
    CASE WHEN wi.CompletedUtc IS NULL THEN NULL
         WHEN CAST(wi.CompletedUtc AS DATE) <= wi.CurrentTargetUtc THEN 1 ELSE 0
    END AS MetCurrentTarget,
    DATEDIFF(DAY, wi.StartedUtc, ISNULL(wi.CompletedUtc, SYSUTCDATETIME())) AS ElapsedCalendarDays,
    (SELECT COUNT(*) FROM wf.ReviewThread rt
      WHERE rt.WorkflowInstanceId = wi.WorkflowInstanceId AND rt.ActionCode = N'Return') AS ReturnCount,
    (SELECT COUNT(*) FROM wf.SlaEvent se
      WHERE se.WorkflowInstanceId = wi.WorkflowInstanceId AND se.EventType = N'Extension') AS ExtensionCount
FROM wf.WorkflowInstance wi
JOIN docaya.Document   d   ON d.DocumentId     = wi.DocumentId
JOIN ref.Department    dep ON dep.DepartmentId = d.DepartmentId
JOIN ref.DocumentClass c   ON c.ClassId        = d.ClassId;
GO

CREATE OR ALTER VIEW rpt.vwStageBottleneck AS
SELECT
    ws.StageNo, ws.RoleCode, r.DisplayNameEn AS RoleName,
    d.DepartmentId, dep.DisplayNameEn AS DepartmentName, wi.RequestType,
    COUNT(*) AS StageExecutions,
    SUM(CASE WHEN ws.Decision = N'Returned' THEN 1 ELSE 0 END) AS ReturnDecisions,
    CAST(AVG(CAST(ws.DurationWorkingMinutes AS FLOAT)) / 480.0 AS DECIMAL(10,2)) AS AvgWorkingDaysAtStage,
    CAST(MAX(CAST(ws.DurationWorkingMinutes AS FLOAT)) / 480.0 AS DECIMAL(10,2)) AS MaxWorkingDaysAtStage,
    CAST(SUM(CAST(ws.DurationWorkingMinutes AS FLOAT)) / 480.0 AS DECIMAL(12,2)) AS TotalWorkingDaysAtStage
FROM wf.WorkflowStage    ws
JOIN wf.WorkflowInstance wi  ON wi.WorkflowInstanceId = ws.WorkflowInstanceId
JOIN docaya.Document     d   ON d.DocumentId          = wi.DocumentId
JOIN ref.Department      dep ON dep.DepartmentId      = d.DepartmentId
LEFT JOIN sec.Role       r   ON r.RoleCode            = ws.RoleCode
WHERE ws.ActedUtc IS NOT NULL
GROUP BY ws.StageNo, ws.RoleCode, r.DisplayNameEn, d.DepartmentId,
         dep.DisplayNameEn, wi.RequestType;
GO

CREATE OR ALTER VIEW rpt.vwPendingApprovals AS
SELECT
    ws.StageId, wi.WorkflowInstanceId, d.DocumentId, d.TrackingNumber, d.BusinessTitle,
    d.DepartmentId, dep.DisplayNameEn AS DepartmentName,
    ws.StageNo, ws.RoleCode, ws.AssignedPrincipalId, p.DisplayName AS AssigneeName,
    ws.EnteredUtc, wi.RequestType, wi.CurrentTargetUtc, wi.IsAtRisk, wi.IsOverdue,
    DATEDIFF(DAY, CAST(SYSUTCDATETIME() AS DATE), wi.CurrentTargetUtc) AS CalendarDaysRemaining
FROM wf.WorkflowStage    ws
JOIN wf.WorkflowInstance wi  ON wi.WorkflowInstanceId = ws.WorkflowInstanceId
JOIN docaya.Document     d   ON d.DocumentId          = wi.DocumentId
JOIN ref.Department      dep ON dep.DepartmentId      = d.DepartmentId
LEFT JOIN sec.Principal  p   ON p.PrincipalId         = ws.AssignedPrincipalId
WHERE ws.ActedUtc IS NULL AND wi.StateCode IN (N'Running', N'Returned');
GO

CREATE OR ALTER VIEW rpt.vwDocumentTimeline AS
SELECT
    rt.WorkflowInstanceId, wi.DocumentId, d.TrackingNumber,
    rt.CreatedUtc AS EventUtc, rt.ActionCode, rt.StageNo, rt.CorrectionPointStageNo,
    rt.ActorPrincipalId, p.DisplayName AS ActorName, rt.ActorRoleCode, rt.CommentText,
    wi.InstanceType, v.VersionLabel AS ResultingVersionLabel
FROM wf.ReviewThread     rt
JOIN wf.WorkflowInstance wi ON wi.WorkflowInstanceId = rt.WorkflowInstanceId
JOIN docaya.Document     d  ON d.DocumentId          = wi.DocumentId
LEFT JOIN sec.Principal  p  ON p.PrincipalId         = rt.ActorPrincipalId
LEFT JOIN docaya.DocumentVersion v ON v.VersionId    = wi.VersionId;
GO

CREATE OR ALTER VIEW rpt.vwAuditActivity AS
SELECT
    a.AuditEventId, a.OccurredUtc, a.ActionCode, a.Outcome,
    a.ActorPrincipalId, p.DisplayName AS ActorName, p.DepartmentId AS ActorDepartmentId,
    a.ExecutorIdentity, a.DocumentId, d.TrackingNumber,
    d.DepartmentId AS DocumentDepartmentId, d.SensitivityId,
    a.RequestId, a.SourceIp
FROM aud.AuditEvent a
LEFT JOIN sec.Principal   p ON p.PrincipalId = a.ActorPrincipalId
LEFT JOIN docaya.Document d ON d.DocumentId  = a.DocumentId;
GO

CREATE OR ALTER VIEW rpt.vwRetentionCompliance AS
SELECT
    d.DocumentId, d.TrackingNumber, d.BusinessTitle,
    d.DepartmentId, dep.DisplayNameEn AS DepartmentName, c.ClassCode,
    rp.PolicyCode AS RetentionPolicy, rp.DispositionAction,
    d.DispositionDueUtc, d.LegalHoldFlag,
    lh.HoldReference, lh.AppliedUtc AS HoldAppliedUtc,
    CASE WHEN d.LegalHoldFlag = 1 THEN N'Blocked by legal hold'
         WHEN d.DispositionDueUtc IS NULL THEN N'No schedule'
         WHEN d.DispositionDueUtc <= CAST(SYSUTCDATETIME() AS DATE) THEN N'Due now'
         WHEN d.DispositionDueUtc <= DATEADD(DAY, 90, CAST(SYSUTCDATETIME() AS DATE))
              THEN N'Due within 90 days'
         ELSE N'Future' END AS DispositionState
FROM docaya.Document d
JOIN ref.Department    dep ON dep.DepartmentId = d.DepartmentId
JOIN ref.DocumentClass c   ON c.ClassId        = d.ClassId
LEFT JOIN ref.RetentionPolicy rp ON rp.RetentionPolicyId = d.RetentionPolicyId
LEFT JOIN docaya.LegalHold lh ON lh.DocumentId = d.DocumentId AND lh.ReleasedUtc IS NULL;
GO

CREATE OR ALTER VIEW rpt.vwIndexHealth AS
SELECT
    ir.IndexRecordId, ir.DocumentId, d.TrackingNumber, ir.VersionId, v.VersionLabel,
    ir.StatusCode AS IndexedStatus, d.StatusCode AS RegistryStatus,
    ir.IsPrimaryResult, ir.ChunkCount, ir.LastBuiltUtc, ir.LastAclRefreshUtc, ir.RemovedUtc,
    er.ModelName, er.ModelVersion,
    CASE WHEN ir.RemovedUtc IS NOT NULL THEN N'Removed'
         WHEN d.StatusCode <> N'Published' THEN N'DRIFT: registry not Published'
         WHEN ir.ChunkCount = 0 THEN N'DRIFT: no passages'
         ELSE N'Healthy' END AS HealthState
FROM idx.DocumentIndexRecord ir
JOIN docaya.Document        d  ON d.DocumentId = ir.DocumentId
JOIN docaya.DocumentVersion v  ON v.VersionId  = ir.VersionId
LEFT JOIN idx.EmbeddingRun  er ON er.EmbeddingRunId = ir.EmbeddingRunId;
GO

CREATE OR ALTER VIEW rpt.vwNotificationDelivery AS
SELECT
    n.NotificationId, n.TypeCode, nt.CategoryCode, n.ChannelCode,
    n.RecipientPrincipalId, p.DepartmentId AS RecipientDepartmentId,
    n.DocumentId, n.BroadcastId, n.CreatedUtc, n.SentUtc, n.ReadUtc,
    CASE WHEN n.ReadUtc IS NOT NULL THEN 1 ELSE 0 END AS IsRead,
    DATEDIFF(MINUTE, n.CreatedUtc, n.SentUtc) AS MinutesToSend
FROM ntf.Notification n
JOIN ntf.NotificationType nt ON nt.TypeCode = n.TypeCode
LEFT JOIN sec.Principal   p  ON p.PrincipalId = n.RecipientPrincipalId;
GO

PRINT '11 · rpt reporting views ready.';
GO
