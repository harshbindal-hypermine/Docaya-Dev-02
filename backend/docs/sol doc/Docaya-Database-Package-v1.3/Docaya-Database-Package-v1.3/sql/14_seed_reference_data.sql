/*==============================================================================
  14 · SEED REFERENCE DATA
  Idempotent MERGE seeds. Values marked (A2)/(A3)/(A4) require client
  confirmation before go-live — see TAD Section 3.4.
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*------------------------------------------------------------- ref.Status */
MERGE ref.Status AS t USING (VALUES
 (N'PendingRegistration', N'Pending registration', 1, 0, 0, 10),
 (N'Draft',               N'Draft',                1, 0, 0, 20),
 (N'Classified',          N'Classified',           1, 0, 0, 30),
 (N'PendingApproval',     N'Pending approval',     1, 0, 0, 40),
 (N'InReview',            N'In review',            1, 0, 0, 50),
 (N'Returned',            N'Returned',             1, 0, 0, 60),
 (N'Approved',            N'Approved',             1, 0, 0, 70),
 (N'Published',           N'Published',            0, 1, 0, 80),
 (N'Superseded',          N'Superseded',           0, 1, 0, 90),
 (N'Expiring',            N'Expiring',             0, 1, 0, 100),
 (N'Archived',            N'Archived',             0, 0, 1, 110),
 (N'Disposed',            N'Disposed',             0, 0, 1, 120)
) AS s (StatusCode, DisplayNameEn, IsStagingState, IsPublished, IsTerminal, SortOrder)
ON t.StatusCode = s.StatusCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn, IsStagingState = s.IsStagingState,
     IsPublished = s.IsPublished, IsTerminal = s.IsTerminal, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (StatusCode, DisplayNameEn, IsStagingState, IsPublished, IsTerminal, SortOrder)
     VALUES (s.StatusCode, s.DisplayNameEn, s.IsStagingState, s.IsPublished, s.IsTerminal, s.SortOrder);
GO

/*--------------------------------------------- ref.StatusTransition (TAD 7.2)
  Any transition NOT listed here is rejected by the domain state machine.   */
MERGE ref.StatusTransition AS t USING (VALUES
 (N'PendingRegistration', N'Draft'),
 (N'Draft',           N'Classified'),
 (N'Classified',      N'PendingApproval'),
 (N'PendingApproval', N'InReview'),
 (N'PendingApproval', N'Returned'),
 (N'InReview',        N'InReview'),
 (N'InReview',        N'Returned'),
 (N'InReview',        N'Approved'),
 (N'Returned',        N'Classified'),
 (N'Returned',        N'PendingApproval'),
 (N'Returned',        N'InReview'),
 (N'Approved',        N'Published'),
 (N'Published',       N'Superseded'),
 (N'Published',       N'Expiring'),
 (N'Published',       N'Archived'),
 (N'Expiring',        N'Published'),
 (N'Expiring',        N'Archived'),
 (N'Superseded',      N'Archived'),
 (N'Archived',        N'Disposed')
) AS s (FromStatusCode, ToStatusCode)
ON t.FromStatusCode = s.FromStatusCode AND t.ToStatusCode = s.ToStatusCode
WHEN NOT MATCHED THEN INSERT (FromStatusCode, ToStatusCode)
     VALUES (s.FromStatusCode, s.ToStatusCode);
GO

/*-------------------------------------------------------- ref.Sensitivity */
MERGE ref.Sensitivity AS t USING (VALUES
 (N'Public',       N'Public',       1, 0, 0),
 (N'Internal',     N'Internal',     2, 0, 0),
 (N'Confidential', N'Confidential', 3, 1, 0),
 (N'Secret',       N'Secret',       4, 1, 1)
) AS s (SensitivityCode, DisplayNameEn, ClearanceRank, RequiresClearance, RequiresStepUpAuth)
ON t.SensitivityCode = s.SensitivityCode
WHEN MATCHED THEN UPDATE SET ClearanceRank = s.ClearanceRank,
     RequiresClearance = s.RequiresClearance, RequiresStepUpAuth = s.RequiresStepUpAuth
WHEN NOT MATCHED THEN INSERT (SensitivityCode, DisplayNameEn, ClearanceRank, RequiresClearance, RequiresStepUpAuth)
     VALUES (s.SensitivityCode, s.DisplayNameEn, s.ClearanceRank, s.RequiresClearance, s.RequiresStepUpAuth);
GO

/*---------------------------------------------------- ref.PublishingScope */
MERGE ref.PublishingScope AS t USING (VALUES
 (N'Departmental',      N'Departmental',       N'OwningDepartment',  10),
 (N'CrossDepartmental', N'Cross-departmental', N'TaggedDepartments', 20),
 (N'OrgWide',           N'Organisation-wide',  N'AllStaff',          30),
 (N'Public',            N'Public',             N'AllStaff',          40)
) AS s (ScopeCode, DisplayNameEn, BroadcastReach, SortOrder)
ON t.ScopeCode = s.ScopeCode
WHEN MATCHED THEN UPDATE SET BroadcastReach = s.BroadcastReach, SortOrder = s.SortOrder
WHEN NOT MATCHED THEN INSERT (ScopeCode, DisplayNameEn, BroadcastReach, SortOrder)
     VALUES (s.ScopeCode, s.DisplayNameEn, s.BroadcastReach, s.SortOrder);
GO

/*------------------------------------------------------------ ref.Priority */
MERGE ref.Priority AS t USING (VALUES
 (N'Routine',  N'Routine',  N'Normal', 30),
 (N'Priority', N'Priority', N'Normal', 20),
 (N'Urgent',   N'Urgent',   N'Urgent', 10)
) AS s (PriorityCode, DisplayNameEn, RequestType, QueueRank)
ON t.PriorityCode = s.PriorityCode
WHEN MATCHED THEN UPDATE SET RequestType = s.RequestType, QueueRank = s.QueueRank
WHEN NOT MATCHED THEN INSERT (PriorityCode, DisplayNameEn, RequestType, QueueRank)
     VALUES (s.PriorityCode, s.DisplayNameEn, s.RequestType, s.QueueRank);
GO

/*----------------------------------------------- ref.DocumentClass  (A2) */
MERGE ref.DocumentClass AS t USING (VALUES
 (N'POLICY',         N'Policy',             N'Policies',            0),
 (N'PROCEDURE',      N'Procedure',          N'Procedures',          0),
 (N'CORRESPONDENCE', N'Correspondence',     N'Correspondence',      0),
 (N'MEMO',           N'Memo / Circular',    N'Memos and Circulars', 0),
 (N'CONTRACT',       N'Contract',           N'Contracts',           1),
 (N'REPORT',         N'Report',             N'Reports',             0),
 (N'HRRECORD',       N'HR Record',          N'HR Records',          1),
 (N'STDEVIDENCE',    N'Standards Evidence', N'Standards Evidence',  0)
) AS s (ClassCode, DisplayNameEn, SharePointLibrary, ThumbnailSuppressed)
ON t.ClassCode = s.ClassCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn,
     SharePointLibrary = s.SharePointLibrary, ThumbnailSuppressed = s.ThumbnailSuppressed
WHEN NOT MATCHED THEN INSERT (ClassCode, DisplayNameEn, SharePointLibrary, ThumbnailSuppressed)
     VALUES (s.ClassCode, s.DisplayNameEn, s.SharePointLibrary, s.ThumbnailSuppressed);
GO

/*---------------------------------------------------- ref.Department  (A2) */
MERGE ref.Department AS t USING (VALUES
 (N'FIN', N'Finance',                N'/sites/docaya-fin'),
 (N'HR',  N'Human Resources',        N'/sites/docaya-hr'),
 (N'LEG', N'Legal',                  N'/sites/docaya-leg'),
 (N'OPS', N'Operations',             N'/sites/docaya-ops'),
 (N'HSE', N'Health and Safety',      N'/sites/docaya-hse'),
 (N'IT',  N'Information Technology', N'/sites/docaya-it')
) AS s (DepartmentCode, DisplayNameEn, SharePointSiteUrl)
ON t.DepartmentCode = s.DepartmentCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn, SharePointSiteUrl = s.SharePointSiteUrl
WHEN NOT MATCHED THEN INSERT (DepartmentCode, DisplayNameEn, SharePointSiteUrl)
     VALUES (s.DepartmentCode, s.DisplayNameEn, s.SharePointSiteUrl);
GO

/*------------------------------------------------------ ref.Standard  (A2) */
MERGE ref.Standard AS t USING (VALUES
 (N'ISO9001',  N'ISO 9001 Quality',               N'ISO-9001'),
 (N'ISO27001', N'ISO 27001 Information Security', N'ISO-27001'),
 (N'ISO45001', N'ISO 45001 Health and Safety',    N'ISO-45001'),
 (N'IMS',      N'Integrated Management System',   N'IMS'),
 (N'AIGOV',    N'AI Governance',                  N'AI-Governance')
) AS s (StandardCode, DisplayNameEn, FolderSegment)
ON t.StandardCode = s.StandardCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn, FolderSegment = s.FolderSegment
WHEN NOT MATCHED THEN INSERT (StandardCode, DisplayNameEn, FolderSegment)
     VALUES (s.StandardCode, s.DisplayNameEn, s.FolderSegment);
GO

/*---------------------------------------------------------------- sec.Role */
MERGE sec.Role AS t USING (VALUES
 (N'SystemAdministrator',    N'System Administrator',         0,0,0,0,1,1,1),
 (N'DepartmentAdmin',        N'Department Administrator',     0,0,0,0,1,1,0),
 (N'RecordsOfficer',         N'Records & Compliance Officer', 0,0,0,1,1,0,0),
 (N'Editor',                 N'Editor / Change Requester',    1,0,0,0,0,0,0),
 (N'DocumentOwner',          N'Document Owner / Approver',    1,1,0,0,0,0,0),
 (N'Assurance',              N'Assurance Reviewer',           1,1,1,0,0,0,0),
 (N'Authoriser',             N'Authoriser',                   1,1,1,0,0,0,1),
 (N'Viewer',                 N'Consumer / Viewer',            0,0,0,0,0,0,0),
 (N'Auditor',                N'Auditor',                      0,0,0,0,1,0,0),
 (N'SupportOperator',        N'Support Operator',             0,0,0,0,0,0,0),
 (N'DeploymentOperator',     N'Deployment Operator',          0,0,0,0,0,0,0),
 (N'EmergencyAdministrator', N'Emergency Administrator',      0,0,0,0,1,1,1)
) AS s (RoleCode, DisplayNameEn, IsWorkflowStageRole, CanApprove, CanExtendSla,
        CanManageRetention, CanViewAudit, CanConfigure, RequiresStepUpAuth)
ON t.RoleCode = s.RoleCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn,
     IsWorkflowStageRole = s.IsWorkflowStageRole, CanApprove = s.CanApprove,
     CanExtendSla = s.CanExtendSla, CanManageRetention = s.CanManageRetention,
     CanViewAudit = s.CanViewAudit, CanConfigure = s.CanConfigure,
     RequiresStepUpAuth = s.RequiresStepUpAuth
WHEN NOT MATCHED THEN INSERT (RoleCode, DisplayNameEn, IsWorkflowStageRole, CanApprove,
     CanExtendSla, CanManageRetention, CanViewAudit, CanConfigure, RequiresStepUpAuth)
     VALUES (s.RoleCode, s.DisplayNameEn, s.IsWorkflowStageRole, s.CanApprove,
             s.CanExtendSla, s.CanManageRetention, s.CanViewAudit, s.CanConfigure,
             s.RequiresStepUpAuth);
GO

/*------------------------------------------- ref.WorkingWeek  (UAE)  (A4)
  UAE weekend since January 2022 = Saturday and Sunday.
  DayOfWeekNo: 1 = Sunday .. 7 = Saturday.                                  */
MERGE ref.WorkingWeek AS t USING (VALUES
 (N'UAE-FED', 1, 1, 0),  -- Sunday    : non-working
 (N'UAE-FED', 1, 2, 1),  -- Monday
 (N'UAE-FED', 1, 3, 1),  -- Tuesday
 (N'UAE-FED', 1, 4, 1),  -- Wednesday
 (N'UAE-FED', 1, 5, 1),  -- Thursday
 (N'UAE-FED', 1, 6, 1),  -- Friday    : working
 (N'UAE-FED', 1, 7, 0)   -- Saturday  : non-working
) AS s (CalendarCode, VersionNo, DayOfWeekNo, IsWorkingDay)
ON t.CalendarCode = s.CalendarCode AND t.VersionNo = s.VersionNo
   AND t.DayOfWeekNo = s.DayOfWeekNo
WHEN MATCHED THEN UPDATE SET IsWorkingDay = s.IsWorkingDay
WHEN NOT MATCHED THEN INSERT (CalendarCode, VersionNo, DayOfWeekNo, IsWorkingDay)
     VALUES (s.CalendarCode, s.VersionNo, s.DayOfWeekNo, s.IsWorkingDay);
GO

/*------------------------------------------- ref.SlaTarget  (TAD 8.3)  (A3)
  Urgent = 12 working days · Normal = 30 working days, end to end.          */
IF NOT EXISTS (SELECT 1 FROM ref.SlaTarget WHERE ScopeType = N'Global' AND RequestType = N'Urgent')
    INSERT INTO ref.SlaTarget (ScopeType, ScopeId, RequestType, TargetWorkingDays, AtRiskWindowDays, CalendarCode)
    VALUES (N'Global', NULL, N'Urgent', 12, 3, N'UAE-FED');
IF NOT EXISTS (SELECT 1 FROM ref.SlaTarget WHERE ScopeType = N'Global' AND RequestType = N'Normal')
    INSERT INTO ref.SlaTarget (ScopeType, ScopeId, RequestType, TargetWorkingDays, AtRiskWindowDays, CalendarCode)
    VALUES (N'Global', NULL, N'Normal', 30, 5, N'UAE-FED');
GO

/*------------------------------------------------- ref.RetentionPolicy (A2) */
MERGE ref.RetentionPolicy AS t USING (VALUES
 (N'RET-STD-7Y',   N'Standard 7 years',       N'TimeBased',  NULL,           84,  N'ReviewThenDelete'),
 (N'RET-CONTRACT', N'Contract + 10 years',    N'EventBased', N'ContractEnd', 120, N'ReviewThenDelete'),
 (N'RET-HR-PERM',  N'HR permanent',           N'TimeBased',  NULL,           1200,N'Archive'),
 (N'RET-CORR-5Y',  N'Correspondence 5 years', N'TimeBased',  NULL,           60,  N'Archive'),
 (N'RET-SUPERSEDE',N'Superseded + 3 years',   N'EventBased', N'Superseded',  36,  N'ReviewThenDelete')
) AS s (PolicyCode, DisplayNameEn, TriggerType, TriggerEvent, RetainMonths, DispositionAction)
ON t.PolicyCode = s.PolicyCode
WHEN MATCHED THEN UPDATE SET DisplayNameEn = s.DisplayNameEn, TriggerType = s.TriggerType,
     TriggerEvent = s.TriggerEvent, RetainMonths = s.RetainMonths,
     DispositionAction = s.DispositionAction
WHEN NOT MATCHED THEN INSERT (PolicyCode, DisplayNameEn, TriggerType, TriggerEvent,
     RetainMonths, DispositionAction)
     VALUES (s.PolicyCode, s.DisplayNameEn, s.TriggerType, s.TriggerEvent,
             s.RetainMonths, s.DispositionAction);
GO

/*--------------------------------------------------- ntf.NotificationType */
MERGE ntf.NotificationType AS t USING (VALUES
 (N'ApprovalRequested',   N'Workflow',     N'Approval requested',        N'InApp,Email,Teams', 0, 1),
 (N'ApprovalGranted',     N'Workflow',     N'Approved',                  N'InApp,Email',       0, 1),
 (N'ReturnedForChanges',  N'Workflow',     N'Returned for changes',      N'InApp,Email,Teams', 0, 1),
 (N'DocumentRegistered',  N'Registration', N'Document registered',       N'InApp,Email',       0, 1),
 (N'DocumentPublished',   N'Publication',  N'Published to SharePoint',   N'InApp,Email',       0, 1),
 (N'DepartmentBroadcast', N'Broadcast',    N'New departmental document', N'InApp,Email,Teams', 0, 1),
 (N'OnboardingReading',   N'Onboarding',   N'Onboarding reading list',   N'InApp,Email',       1, 1),
 (N'SlaAtRisk',           N'Sla',          N'Request at risk',           N'InApp,Email,Teams', 0, 1),
 (N'SlaOverdue',          N'Sla',          N'Request overdue',           N'InApp,Email,Teams', 0, 1),
 (N'SlaExtensionGranted', N'Sla',          N'Target extended',           N'InApp,Email',       0, 1),
 (N'ExpiryReminder',      N'Expiry',       N'Document expiring',         N'InApp,Email',       0, 1),
 (N'RetentionDue',        N'Expiry',       N'Retention action due',      N'InApp,Email',       0, 1),
 (N'PermissionChanged',   N'Security',     N'Permission changed',        N'InApp,Email,Push',  1, 0),
 (N'UnusualAccess',       N'Security',     N'Unusual access detected',   N'InApp,Email,Push',  1, 0),
 (N'ExternalShare',       N'Security',     N'External share',            N'InApp,Email,Push',  1, 0),
 (N'SystemMaintenance',   N'System',       N'System maintenance',        N'InApp,Email',       0, 1)
) AS s (TypeCode, CategoryCode, DisplayNameEn, DefaultChannels, IsMandatory, RespectQuietHours)
ON t.TypeCode = s.TypeCode
WHEN MATCHED THEN UPDATE SET CategoryCode = s.CategoryCode, DisplayNameEn = s.DisplayNameEn,
     DefaultChannels = s.DefaultChannels, IsMandatory = s.IsMandatory,
     RespectQuietHours = s.RespectQuietHours
WHEN NOT MATCHED THEN INSERT (TypeCode, CategoryCode, DisplayNameEn, DefaultChannels,
     IsMandatory, RespectQuietHours)
     VALUES (s.TypeCode, s.CategoryCode, s.DisplayNameEn, s.DefaultChannels,
             s.IsMandatory, s.RespectQuietHours);
GO

/*--------------------------- DEFAULT 4-STAGE REVIEW CHAIN  (TAD 8.1)  (A3)
  Editor -> Document Owner -> Assurance -> Authoriser. Organisation-wide for
  V1; departmental variants are added post-go-live via the Admin Center.    */
IF NOT EXISTS (SELECT 1 FROM wf.RouteDefinition WHERE RouteCode = N'GLOBAL-4STAGE')
BEGIN
    INSERT INTO wf.RouteDefinition (RouteCode, ScopeType, StageCount, VersionNo, IsActive)
    VALUES (N'GLOBAL-4STAGE', N'Global', 4, 1, 1);

    DECLARE @rid INT = SCOPE_IDENTITY();
    INSERT INTO wf.RouteStage (RouteDefinitionId, StageNo, RoleCode, StageNameEn,
                               IsMandatory, PatternCode, CanExtendSla, IsFinalApproval)
    VALUES
      (@rid, 1, N'Editor',        N'Submission',          1, N'Sequential', 0, 0),
      (@rid, 2, N'DocumentOwner', N'Owner review',        1, N'Sequential', 0, 0),
      (@rid, 3, N'Assurance',     N'Assurance review',    1, N'Sequential', 1, 0),
      (@rid, 4, N'Authoriser',    N'Final authorisation', 1, N'Sequential', 1, 1);
END
GO

PRINT '14 · reference data seeded.';
GO
