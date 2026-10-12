/*==============================================================================
  09 · aud  ·  APPEND-ONLY HASH-CHAINED AUDIT
  No UPDATE or DELETE grant exists for any application principal — that is
  what makes the chain defensible. A trigger enforces the same rule as
  defence in depth even for a mis-granted principal.        TAD 11.9.1 / 15.1
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*----------------------------------------------------------- aud.AuditEvent
  Hash = SHA2_256( PrevHash || canonical(payload) ), so any alteration to an
  earlier row breaks every subsequent link and is immediately detectable.    */
IF OBJECT_ID('aud.AuditEvent') IS NULL
CREATE TABLE aud.AuditEvent (
    AuditEventId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditEvent PRIMARY KEY,
    DocumentId       UNIQUEIDENTIFIER NULL,
    VersionId        UNIQUEIDENTIFIER NULL,
    ActorPrincipalId UNIQUEIDENTIFIER NOT NULL,   -- the REAL user
    ExecutorIdentity NVARCHAR(128)    NOT NULL,   -- the system identity that acted
    ActionCode       NVARCHAR(48)     NOT NULL,
    ObjectType       NVARCHAR(48)     NULL,
    ObjectRef        NVARCHAR(200)    NULL,
    Outcome          NVARCHAR(16)     NOT NULL,
    RequestId        NVARCHAR(64)     NOT NULL,
    SourceIp         NVARCHAR(45)     NULL,
    UserAgent        NVARCHAR(400)    NULL,
    PolicyVersionId  INT              NULL,
    PayloadJson      NVARCHAR(MAX)    NULL,
    PrevHash         BINARY(32)       NOT NULL,
    Hash             BINARY(32)       NOT NULL,
    OccurredUtc      DATETIME2(3)     NOT NULL CONSTRAINT DF_Audit_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT CK_Audit_Outcome CHECK (Outcome IN (N'Success', N'Denied', N'Failed')),
    CONSTRAINT CK_Audit_Json    CHECK (PayloadJson IS NULL OR ISJSON(PayloadJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Audit_Doc_Time' AND object_id = OBJECT_ID(N'aud.AuditEvent'))
CREATE NONCLUSTERED INDEX IX_Audit_Doc_Time ON aud.AuditEvent (DocumentId, OccurredUtc DESC)
    INCLUDE (ActionCode, ActorPrincipalId, Outcome) WHERE DocumentId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Audit_Actor' AND object_id = OBJECT_ID(N'aud.AuditEvent'))
CREATE NONCLUSTERED INDEX IX_Audit_Actor ON aud.AuditEvent (ActorPrincipalId, OccurredUtc DESC) INCLUDE (ActionCode, DocumentId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Audit_Time' AND object_id = OBJECT_ID(N'aud.AuditEvent'))
CREATE NONCLUSTERED INDEX IX_Audit_Time ON aud.AuditEvent (OccurredUtc DESC) INCLUDE (ActionCode, ActorPrincipalId, DocumentId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Audit_Request' AND object_id = OBJECT_ID(N'aud.AuditEvent'))
CREATE NONCLUSTERED INDEX IX_Audit_Request ON aud.AuditEvent (RequestId);
GO

/*---------------------------------------------------- aud.ChainCheckpoint */
IF OBJECT_ID('aud.ChainCheckpoint') IS NULL
CREATE TABLE aud.ChainCheckpoint (
    CheckpointId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ChainCheckpoint PRIMARY KEY,
    UpToAuditEventId BIGINT       NOT NULL,
    ChainHash        BINARY(32)   NOT NULL,
    EventCount       BIGINT       NOT NULL,
    VerifiedUtc      DATETIME2(3) NULL,
    VerificationOk   BIT          NULL,
    CreatedUtc       DATETIME2(3) NOT NULL CONSTRAINT DF_Checkpoint_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_ChainCheckpoint UNIQUE (UpToAuditEventId)
);
GO

/*--------------------------------------------------------- aud.AuditExport */
IF OBJECT_ID('aud.AuditExport') IS NULL
CREATE TABLE aud.AuditExport (
    ExportId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AuditExport PRIMARY KEY,
    ExportScope  NVARCHAR(24)   NOT NULL,
    ScopeRef     NVARCHAR(200)  NULL,
    FromUtc      DATETIME2(3)   NULL,
    ToUtc        DATETIME2(3)   NULL,
    RecordCount  BIGINT         NOT NULL CONSTRAINT DF_Export_Count DEFAULT (0),
    ExportUri    NVARCHAR(1000) NULL,
    ExportHash   BINARY(32)     NULL,
    RequestedBy  UNIQUEIDENTIFIER NOT NULL,
    RequestedUtc DATETIME2(3)   NOT NULL CONSTRAINT DF_Export_Req DEFAULT (SYSUTCDATETIME()),
    CompletedUtc DATETIME2(3)   NULL,
    CONSTRAINT FK_Export_RequestedBy FOREIGN KEY (RequestedBy) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Export_Scope CHECK (ExportScope IN (N'Document', N'User', N'DateRange'))
);
GO

/*---------------------------------------------------- IMMUTABILITY TRIGGER
  Defence in depth. Even if a principal were mis-granted UPDATE or DELETE,
  this trigger blocks the statement and rolls the transaction back.         */
IF OBJECT_ID('aud.TR_AuditEvent_Immutable') IS NOT NULL
    DROP TRIGGER aud.TR_AuditEvent_Immutable;
GO
CREATE TRIGGER aud.TR_AuditEvent_Immutable
ON aud.AuditEvent
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    RAISERROR (N'aud.AuditEvent is append-only. UPDATE and DELETE are prohibited by design (TAD 11.9.1).', 16, 1);
    ROLLBACK TRANSACTION;
END;
GO

PRINT '09 · aud audit schema ready (append-only enforced by GRANT + trigger).';
GO
