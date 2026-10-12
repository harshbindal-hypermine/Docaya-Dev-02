/*==============================================================================
  10 · ops  ·  OPERATIONAL INTEGRITY
  Outbox, idempotency, dead-letter, promotion ledger, configuration sets and
  job runs — cross-cutting concerns kept OUT of business tables.  TAD 11.9
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*--------------------------------------------------------- ops.OutboxMessage
  State change and domain event are written in ONE SQL transaction and
  dispatched afterwards, so a document can never reach Approved without the
  promotion event being raised.                                              */
IF OBJECT_ID('ops.OutboxMessage') IS NULL
CREATE TABLE ops.OutboxMessage (
    OutboxId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OutboxMessage PRIMARY KEY,
    AggregateType NVARCHAR(48)     NOT NULL,
    AggregateId   UNIQUEIDENTIFIER NOT NULL,
    EventType     NVARCHAR(64)     NOT NULL,
    PayloadJson   NVARCHAR(MAX)    NOT NULL,
    CorrelationId NVARCHAR(64)     NOT NULL,
    SessionKey    NVARCHAR(128)    NULL,
    CreatedUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_Outbox_Created DEFAULT (SYSUTCDATETIME()),
    DispatchedUtc DATETIME2(3)     NULL,
    Attempts      INT              NOT NULL CONSTRAINT DF_Outbox_Attempts DEFAULT (0),
    LastError     NVARCHAR(MAX)    NULL,
    CONSTRAINT CK_Outbox_Json CHECK (ISJSON(PayloadJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Outbox_Pending' AND object_id = OBJECT_ID(N'ops.OutboxMessage'))
CREATE NONCLUSTERED INDEX IX_Outbox_Pending ON ops.OutboxMessage (CreatedUtc)
    INCLUDE (EventType, AggregateId, PayloadJson, SessionKey)
    WHERE DispatchedUtc IS NULL;
GO

/*-------------------------------------------------------- ops.IdempotencyKey */
IF OBJECT_ID('ops.IdempotencyKey') IS NULL
CREATE TABLE ops.IdempotencyKey (
    KeyValue    NVARCHAR(200)    NOT NULL CONSTRAINT PK_IdempotencyKey PRIMARY KEY,
    Endpoint    NVARCHAR(200)    NOT NULL,
    PrincipalId UNIQUEIDENTIFIER NULL,
    ResultRef   NVARCHAR(400)    NULL,
    StatusCode  INT              NULL,
    CreatedUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_Idem_Created DEFAULT (SYSUTCDATETIME()),
    ExpiresUtc  DATETIME2(3)     NOT NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Idempotency_Expiry' AND object_id = OBJECT_ID(N'ops.IdempotencyKey'))
CREATE NONCLUSTERED INDEX IX_Idempotency_Expiry ON ops.IdempotencyKey (ExpiresUtc);
GO

/*------------------------------------------------------- ops.PromotionLedger
  THE exactly-once guarantee. IdempotencyKey is UNIQUE: a retried or
  duplicated command finds the existing row and stops, so a second SharePoint
  item can never be created.                               TAD 13.5 / 16     */
IF OBJECT_ID('ops.PromotionLedger') IS NULL
CREATE TABLE ops.PromotionLedger (
    PromotionId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PromotionLedger PRIMARY KEY,
    DocumentId       UNIQUEIDENTIFIER NOT NULL,
    VersionId        UNIQUEIDENTIFIER NULL,
    IdempotencyKey   NVARCHAR(200)    NOT NULL,
    StagedHash       BINARY(32)       NOT NULL,
    PublishedHash    BINARY(32)       NULL,
    HashMatched      BIT              NULL,
    SpSiteId         NVARCHAR(128)    NULL,
    SpDriveId        NVARCHAR(128)    NULL,
    SpItemId         NVARCHAR(128)    NULL,
    SpWebUrl         NVARCHAR(1000)   NULL,
    SpVersionLabel   NVARCHAR(20)     NULL,
    ResultCode       NVARCHAR(24)     NOT NULL CONSTRAINT DF_Promo_Result DEFAULT (N'Pending'),
    Attempts         INT              NOT NULL CONSTRAINT DF_Promo_Attempts DEFAULT (0),
    LastError        NVARCHAR(MAX)    NULL,
    ExecutorIdentity NVARCHAR(128)    NULL,
    ActorPrincipalId UNIQUEIDENTIFIER NULL,
    StartedUtc       DATETIME2(3)     NOT NULL CONSTRAINT DF_Promo_Start DEFAULT (SYSUTCDATETIME()),
    CompletedUtc     DATETIME2(3)     NULL,
    CONSTRAINT UQ_PromotionLedger_Idempotency UNIQUE (IdempotencyKey),
    CONSTRAINT FK_Promo_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Promo_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_Promo_Actor    FOREIGN KEY (ActorPrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Promo_Result CHECK (ResultCode IN
        (N'Pending', N'Succeeded', N'Quarantined', N'Failed')),
    /* A success REQUIRES a verified hash match */
    CONSTRAINT CK_Promo_SuccessNeedsHash CHECK
        (ResultCode <> N'Succeeded' OR (HashMatched = 1 AND PublishedHash IS NOT NULL))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Promotion_Document' AND object_id = OBJECT_ID(N'ops.PromotionLedger'))
CREATE NONCLUSTERED INDEX IX_Promotion_Document ON ops.PromotionLedger (DocumentId, StartedUtc DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Promotion_Open' AND object_id = OBJECT_ID(N'ops.PromotionLedger'))
CREATE NONCLUSTERED INDEX IX_Promotion_Open ON ops.PromotionLedger (ResultCode, StartedUtc)
    WHERE ResultCode IN (N'Pending', N'Quarantined', N'Failed');
GO

/*------------------------------------------------------------- ops.DeadLetter */
IF OBJECT_ID('ops.DeadLetter') IS NULL
CREATE TABLE ops.DeadLetter (
    DeadLetterId  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DeadLetter PRIMARY KEY,
    Source        NVARCHAR(128)    NOT NULL,
    MessageId     NVARCHAR(200)    NULL,
    CorrelationId NVARCHAR(64)     NULL,
    AggregateId   UNIQUEIDENTIFIER NULL,
    PayloadJson   NVARCHAR(MAX)    NULL,
    ErrorText     NVARCHAR(MAX)    NULL,
    Attempts      INT              NOT NULL CONSTRAINT DF_Dlq_Attempts DEFAULT (0),
    EnqueuedUtc   DATETIME2(3)     NOT NULL CONSTRAINT DF_Dlq_Enq DEFAULT (SYSUTCDATETIME()),
    ReplayedUtc   DATETIME2(3)     NULL,
    ReplayedBy    UNIQUEIDENTIFIER NULL,
    CONSTRAINT FK_Dlq_ReplayedBy FOREIGN KEY (ReplayedBy) REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_DeadLetter_Open' AND object_id = OBJECT_ID(N'ops.DeadLetter'))
CREATE NONCLUSTERED INDEX IX_DeadLetter_Open ON ops.DeadLetter (EnqueuedUtc) WHERE ReplayedUtc IS NULL;
GO

/*--------------------------------------------------------- ops.ConfigurationSet */
IF OBJECT_ID('ops.ConfigurationSet') IS NULL
CREATE TABLE ops.ConfigurationSet (
    ConfigurationSetId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ConfigurationSet PRIMARY KEY,
    SetCode        NVARCHAR(48)     NOT NULL,
    VersionNo      INT              NOT NULL,
    PayloadJson    NVARCHAR(MAX)    NOT NULL,
    ReleaseVersion NVARCHAR(32)     NULL,
    PublishedUtc   DATETIME2(3)     NOT NULL CONSTRAINT DF_Config_Pub DEFAULT (SYSUTCDATETIME()),
    PublishedBy    UNIQUEIDENTIFIER NULL,
    IsCurrent      BIT              NOT NULL CONSTRAINT DF_Config_Cur DEFAULT (0),
    CONSTRAINT UQ_ConfigurationSet UNIQUE (SetCode, VersionNo),
    CONSTRAINT FK_Config_By FOREIGN KEY (PublishedBy) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Config_Json CHECK (ISJSON(PayloadJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_ConfigurationSet_Current' AND object_id = OBJECT_ID(N'ops.ConfigurationSet'))
CREATE UNIQUE NONCLUSTERED INDEX UX_ConfigurationSet_Current ON ops.ConfigurationSet (SetCode) WHERE IsCurrent = 1;
GO

/*---------------------------------------------------------------- ops.JobRun */
IF OBJECT_ID('ops.JobRun') IS NULL
CREATE TABLE ops.JobRun (
    JobRunId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_JobRun PRIMARY KEY,
    JobName      NVARCHAR(96)  NOT NULL,
    StartedUtc   DATETIME2(3)  NOT NULL CONSTRAINT DF_Job_Start DEFAULT (SYSUTCDATETIME()),
    CompletedUtc DATETIME2(3)  NULL,
    Outcome      NVARCHAR(16)  NULL,
    ItemsRead    INT           NOT NULL CONSTRAINT DF_Job_Read DEFAULT (0),
    ItemsChanged INT           NOT NULL CONSTRAINT DF_Job_Changed DEFAULT (0),
    DurationMs   INT           NULL,
    DetailJson   NVARCHAR(MAX) NULL,
    CONSTRAINT CK_Job_Outcome CHECK (Outcome IS NULL OR Outcome IN (N'Success', N'Partial', N'Failed')),
    CONSTRAINT CK_Job_Json CHECK (DetailJson IS NULL OR ISJSON(DetailJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_JobRun_Name_Time' AND object_id = OBJECT_ID(N'ops.JobRun'))
CREATE NONCLUSTERED INDEX IX_JobRun_Name_Time ON ops.JobRun (JobName, StartedUtc DESC);
GO

PRINT '10 · ops operational schema ready.';
GO
