/*==============================================================================
  06 · wf  ·  WORKFLOW, REVIEW CHAIN, THREAD AND SLA
  High write frequency and a distinct retention profile; isolated so the
  registry tables stay narrow and index-stable.            TAD 8 / 11.6
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*-------------------------------------------------------- wf.RouteDefinition
  The VERSIONED configured chain. Changing a route is a configuration action,
  never an engineering change.                                               */
IF OBJECT_ID('wf.RouteDefinition') IS NULL
CREATE TABLE wf.RouteDefinition (
    RouteDefinitionId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RouteDefinition PRIMARY KEY,
    RouteCode         NVARCHAR(48) NOT NULL,
    ScopeType         NVARCHAR(24) NOT NULL,
    DocumentClassId   INT          NULL,
    DepartmentId      INT          NULL,
    StageCount        TINYINT      NOT NULL,
    VersionNo         INT          NOT NULL,
    EffectiveFromUtc  DATETIME2(3) NOT NULL CONSTRAINT DF_Route_From DEFAULT (SYSUTCDATETIME()),
    EffectiveToUtc    DATETIME2(3) NULL,
    IsActive          BIT          NOT NULL CONSTRAINT DF_Route_Active DEFAULT (1),
    PublishedBy       UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_RouteDefinition UNIQUE (RouteCode, VersionNo),
    CONSTRAINT FK_Route_Class FOREIGN KEY (DocumentClassId) REFERENCES ref.DocumentClass(ClassId),
    CONSTRAINT FK_Route_Dept  FOREIGN KEY (DepartmentId)    REFERENCES ref.Department(DepartmentId),
    CONSTRAINT FK_Route_By    FOREIGN KEY (PublishedBy)     REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Route_Scope  CHECK (ScopeType IN (N'Global', N'Class', N'Department')),
    CONSTRAINT CK_Route_Stages CHECK (StageCount BETWEEN 3 AND 4)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Route_Resolution' AND object_id = OBJECT_ID(N'wf.RouteDefinition'))
CREATE NONCLUSTERED INDEX IX_Route_Resolution ON wf.RouteDefinition (ScopeType, DocumentClassId, DepartmentId, IsActive)
    INCLUDE (RouteDefinitionId, StageCount, VersionNo);
GO

/*------------------------------------------------------------- wf.RouteStage */
IF OBJECT_ID('wf.RouteStage') IS NULL
CREATE TABLE wf.RouteStage (
    RouteStageId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RouteStage PRIMARY KEY,
    RouteDefinitionId INT          NOT NULL,
    StageNo           TINYINT      NOT NULL,
    RoleCode          NVARCHAR(48) NOT NULL,
    StageNameEn       NVARCHAR(96) NULL,
    StageNameAr       NVARCHAR(96) NULL,
    IsMandatory       BIT          NOT NULL CONSTRAINT DF_Stage_Mand DEFAULT (1),
    PatternCode       NVARCHAR(24) NOT NULL CONSTRAINT DF_Stage_Pattern DEFAULT (N'Sequential'),
    QuorumCount       INT          NULL,
    ConditionExpr     NVARCHAR(MAX) NULL,
    CanExtendSla      BIT          NOT NULL CONSTRAINT DF_Stage_Ext DEFAULT (0),
    IsFinalApproval   BIT          NOT NULL CONSTRAINT DF_Stage_Final DEFAULT (0),
    CONSTRAINT UQ_RouteStage UNIQUE (RouteDefinitionId, StageNo),
    CONSTRAINT FK_RouteStage_Route FOREIGN KEY (RouteDefinitionId)
        REFERENCES wf.RouteDefinition(RouteDefinitionId) ON DELETE CASCADE,
    CONSTRAINT FK_RouteStage_Role FOREIGN KEY (RoleCode) REFERENCES sec.Role(RoleCode),
    CONSTRAINT CK_Stage_Pattern CHECK (PatternCode IN
        (N'Sequential', N'Parallel', N'Quorum', N'Conditional')),
    CONSTRAINT CK_Stage_Quorum CHECK (PatternCode <> N'Quorum' OR QuorumCount >= 1),
    CONSTRAINT CK_Stage_Cond   CHECK (ConditionExpr IS NULL OR ISJSON(ConditionExpr) = 1)
);
GO

/*----------------------------------------------------- wf.WorkflowInstance */
IF OBJECT_ID('wf.WorkflowInstance') IS NULL
CREATE TABLE wf.WorkflowInstance (
    WorkflowInstanceId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_WorkflowInstance PRIMARY KEY
                           CONSTRAINT DF_WfInst_Id DEFAULT (NEWSEQUENTIALID()),
    DocumentId         UNIQUEIDENTIFIER NOT NULL,
    VersionId          UNIQUEIDENTIFIER NULL,
    RouteDefinitionId  INT              NOT NULL,
    InstanceType       NVARCHAR(24)     NOT NULL CONSTRAINT DF_WfInst_Type DEFAULT (N'NewDocument'),
    RequestType        NVARCHAR(16)     NOT NULL,
    BaseVersionId      UNIQUEIDENTIFIER NULL,
    Rationale          NVARCHAR(MAX)    NULL,
    CalendarCode       NVARCHAR(24)     NOT NULL CONSTRAINT DF_WfInst_Cal DEFAULT (N'UAE-FED'),
    CalendarVersionNo  INT              NOT NULL CONSTRAINT DF_WfInst_CalVer DEFAULT (1),
    OriginalTargetUtc  DATE             NOT NULL,
    CurrentTargetUtc   DATE             NOT NULL,
    StateCode          NVARCHAR(24)     NOT NULL,
    CurrentStageNo     TINYINT          NULL,
    IsAtRisk           BIT              NOT NULL CONSTRAINT DF_WfInst_Risk DEFAULT (0),
    IsOverdue          BIT              NOT NULL CONSTRAINT DF_WfInst_Over DEFAULT (0),
    StartedUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_WfInst_Start DEFAULT (SYSUTCDATETIME()),
    CompletedUtc       DATETIME2(3)     NULL,
    StartedBy          UNIQUEIDENTIFIER NOT NULL,
    RowVersion         ROWVERSION       NOT NULL,
    CONSTRAINT FK_WfInst_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_WfInst_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_WfInst_Base     FOREIGN KEY (BaseVersionId) REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_WfInst_Route    FOREIGN KEY (RouteDefinitionId)
        REFERENCES wf.RouteDefinition(RouteDefinitionId),
    CONSTRAINT FK_WfInst_StartedBy FOREIGN KEY (StartedBy) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_WfInst_ReqType CHECK (RequestType IN (N'Urgent', N'Normal')),
    CONSTRAINT CK_WfInst_Type    CHECK (InstanceType IN (N'NewDocument', N'NewRevision')),
    CONSTRAINT CK_WfInst_State   CHECK (StateCode IN
        (N'Running', N'Returned', N'Approved', N'Cancelled', N'Completed')),
    CONSTRAINT CK_WfInst_Target  CHECK (CurrentTargetUtc >= OriginalTargetUtc),
    CONSTRAINT CK_WfInst_BaseVersion CHECK
        (InstanceType <> N'NewRevision' OR BaseVersionId IS NOT NULL)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_WfInstance_ActivePerDoc' AND object_id = OBJECT_ID(N'wf.WorkflowInstance'))
CREATE UNIQUE NONCLUSTERED INDEX UX_WfInstance_ActivePerDoc ON wf.WorkflowInstance (DocumentId) WHERE StateCode IN (N'Running', N'Returned');
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WfInstance_Open' AND object_id = OBJECT_ID(N'wf.WorkflowInstance'))
CREATE NONCLUSTERED INDEX IX_WfInstance_Open ON wf.WorkflowInstance (StateCode, CurrentTargetUtc)
    INCLUDE (DocumentId, CurrentStageNo, RequestType, IsAtRisk, IsOverdue)
    WHERE CompletedUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WfInstance_Document' AND object_id = OBJECT_ID(N'wf.WorkflowInstance'))
CREATE NONCLUSTERED INDEX IX_WfInstance_Document ON wf.WorkflowInstance (DocumentId, StartedUtc DESC);
GO

/*-------------------------------------------------------- wf.WorkflowStage
  DurationWorkingMinutes attributes delay to a SPECIFIC stage, which is what
  makes bottleneck reporting honest.                                         */
IF OBJECT_ID('wf.WorkflowStage') IS NULL
CREATE TABLE wf.WorkflowStage (
    StageId                UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_WorkflowStage PRIMARY KEY
                               CONSTRAINT DF_WfStage_Id DEFAULT (NEWSEQUENTIALID()),
    WorkflowInstanceId     UNIQUEIDENTIFIER NOT NULL,
    StageNo                TINYINT      NOT NULL,
    RoleCode               NVARCHAR(48) NOT NULL,
    AssignedPrincipalId    UNIQUEIDENTIFIER NULL,
    DelegatedFromId        UNIQUEIDENTIFIER NULL,
    EnteredUtc             DATETIME2(3) NOT NULL CONSTRAINT DF_WfStage_Enter DEFAULT (SYSUTCDATETIME()),
    ActedUtc               DATETIME2(3) NULL,
    DurationWorkingMinutes INT          NULL,
    Decision               NVARCHAR(16) NULL,
    QuorumMet              BIT          NULL,
    AttemptNo              INT          NOT NULL CONSTRAINT DF_WfStage_Attempt DEFAULT (1),
    CONSTRAINT FK_WfStage_Instance FOREIGN KEY (WorkflowInstanceId)
        REFERENCES wf.WorkflowInstance(WorkflowInstanceId),
    CONSTRAINT FK_WfStage_Assignee FOREIGN KEY (AssignedPrincipalId)
        REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_WfStage_Role FOREIGN KEY (RoleCode) REFERENCES sec.Role(RoleCode),
    CONSTRAINT CK_WfStage_Decision CHECK (Decision IS NULL
        OR Decision IN (N'Approved', N'Returned', N'Reassigned')),
    CONSTRAINT CK_WfStage_Duration CHECK (DurationWorkingMinutes IS NULL OR DurationWorkingMinutes >= 0)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WfStage_Queue' AND object_id = OBJECT_ID(N'wf.WorkflowStage'))
CREATE NONCLUSTERED INDEX IX_WfStage_Queue ON wf.WorkflowStage (AssignedPrincipalId, ActedUtc)
    INCLUDE (WorkflowInstanceId, StageNo, RoleCode, EnteredUtc)
    WHERE ActedUtc IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WfStage_Instance' AND object_id = OBJECT_ID(N'wf.WorkflowStage'))
CREATE NONCLUSTERED INDEX IX_WfStage_Instance ON wf.WorkflowStage (WorkflowInstanceId, StageNo, AttemptNo);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WfStage_Completed' AND object_id = OBJECT_ID(N'wf.WorkflowStage'))
CREATE NONCLUSTERED INDEX IX_WfStage_Completed ON wf.WorkflowStage (ActedUtc) INCLUDE (StageNo, RoleCode, DurationWorkingMinutes)
    WHERE ActedUtc IS NOT NULL;
GO

/*---------------------------------------------------------- wf.ReviewThread */
IF OBJECT_ID('wf.ReviewThread') IS NULL
CREATE TABLE wf.ReviewThread (
    ThreadEntryId          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReviewThread PRIMARY KEY,
    WorkflowInstanceId     UNIQUEIDENTIFIER NOT NULL,
    StageId                UNIQUEIDENTIFIER NULL,
    StageNo                TINYINT      NULL,
    ActionCode             NVARCHAR(32) NOT NULL,
    CommentText            NVARCHAR(MAX) NULL,
    CorrectionPointStageNo TINYINT      NULL,
    ActorPrincipalId       UNIQUEIDENTIFIER NOT NULL,
    ActorRoleCode          NVARCHAR(48) NULL,
    CreatedUtc             DATETIME2(3) NOT NULL CONSTRAINT DF_Thread_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Thread_Instance FOREIGN KEY (WorkflowInstanceId)
        REFERENCES wf.WorkflowInstance(WorkflowInstanceId),
    CONSTRAINT FK_Thread_Stage FOREIGN KEY (StageId) REFERENCES wf.WorkflowStage(StageId),
    CONSTRAINT FK_Thread_Actor FOREIGN KEY (ActorPrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Thread_Action CHECK (ActionCode IN
        (N'Submit', N'Approve', N'Return', N'Resubmit', N'Reassign', N'Extend', N'Comment')),
    /* MANDATORY comment + correction point on a return (FR-WF-03) */
    CONSTRAINT CK_Thread_ReturnComment CHECK
        (ActionCode <> N'Return'
         OR (CommentText IS NOT NULL AND LEN(LTRIM(RTRIM(CommentText))) > 0
             AND CorrectionPointStageNo IS NOT NULL))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Thread_Instance_Time' AND object_id = OBJECT_ID(N'wf.ReviewThread'))
CREATE NONCLUSTERED INDEX IX_Thread_Instance_Time ON wf.ReviewThread (WorkflowInstanceId, CreatedUtc)
    INCLUDE (ActionCode, StageNo, ActorPrincipalId);
GO

/*-------------------------------------------------------------- wf.SlaEvent
  At-risk, overdue and extension events, each retained separately so the
  ORIGINAL target is never lost.                                             */
IF OBJECT_ID('wf.SlaEvent') IS NULL
CREATE TABLE wf.SlaEvent (
    SlaEventId         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SlaEvent PRIMARY KEY,
    WorkflowInstanceId UNIQUEIDENTIFIER NOT NULL,
    EventType          NVARCHAR(24) NOT NULL,
    PreviousTargetUtc  DATE         NULL,
    NewTargetUtc       DATE         NULL,
    RemainingDays      INT          NULL,
    ReasonText         NVARCHAR(MAX) NULL,
    ActorPrincipalId   UNIQUEIDENTIFIER NULL,
    ActorRoleCode      NVARCHAR(48) NULL,
    RaisedUtc          DATETIME2(3) NOT NULL CONSTRAINT DF_Sla_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_SlaEvent_Instance FOREIGN KEY (WorkflowInstanceId)
        REFERENCES wf.WorkflowInstance(WorkflowInstanceId),
    CONSTRAINT FK_SlaEvent_Actor FOREIGN KEY (ActorPrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Sla_EventType CHECK (EventType IN
        (N'AtRisk', N'Overdue', N'Extension', N'Recalculated')),
    /* An extension MUST record who authorised it and why (FR-WF-07) */
    CONSTRAINT CK_Sla_ExtensionReason CHECK
        (EventType <> N'Extension'
         OR (ReasonText IS NOT NULL AND LEN(LTRIM(RTRIM(ReasonText))) > 0
             AND ActorPrincipalId IS NOT NULL AND NewTargetUtc IS NOT NULL))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SlaEvent_Instance' AND object_id = OBJECT_ID(N'wf.SlaEvent'))
CREATE NONCLUSTERED INDEX IX_SlaEvent_Instance ON wf.SlaEvent (WorkflowInstanceId, RaisedUtc DESC) INCLUDE (EventType);
GO

PRINT '06 · wf workflow schema ready.';
GO
