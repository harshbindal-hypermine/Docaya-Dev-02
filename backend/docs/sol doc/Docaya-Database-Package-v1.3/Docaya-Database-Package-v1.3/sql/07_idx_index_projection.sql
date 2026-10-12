/*==============================================================================
  07 · idx  ·  SEARCH INDEX PROJECTION STATE   (DERIVED · REBUILDABLE)
  Holding projection state in SQL means the platform can answer "is the index
  correct?" without calling Azure AI Search, can rebuild deterministically
  after a model upgrade, and can PROVE no unapproved version was ever present.
  TAD 11.8 / 12
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*--------------------------------------------------------- idx.EmbeddingRun */
IF OBJECT_ID('idx.EmbeddingRun') IS NULL
CREATE TABLE idx.EmbeddingRun (
    EmbeddingRunId UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_EmbeddingRun PRIMARY KEY
                       CONSTRAINT DF_EmbRun_Id DEFAULT (NEWSEQUENTIALID()),
    ModelName      NVARCHAR(128) NOT NULL,
    ModelVersion   NVARCHAR(64)  NOT NULL,
    Dimensions     INT           NOT NULL,
    RegionCode     NVARCHAR(32)  NOT NULL,
    StartedUtc     DATETIME2(3)  NOT NULL CONSTRAINT DF_EmbRun_Start DEFAULT (SYSUTCDATETIME()),
    CompletedUtc   DATETIME2(3)  NULL,
    DocumentCount  INT           NOT NULL CONSTRAINT DF_EmbRun_Count DEFAULT (0),
    RunReason      NVARCHAR(64)  NULL,
    IsCurrent      BIT           NOT NULL CONSTRAINT DF_EmbRun_Current DEFAULT (0),
    CONSTRAINT CK_EmbRun_Dims CHECK (Dimensions > 0)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_EmbeddingRun_Current' AND object_id = OBJECT_ID(N'idx.EmbeddingRun'))
CREATE UNIQUE NONCLUSTERED INDEX UX_EmbeddingRun_Current ON idx.EmbeddingRun (IsCurrent) WHERE IsCurrent = 1;
GO

/*--------------------------------------------------- idx.DocumentIndexRecord
  ONE row per APPROVED version present in the search index. The Published
  event is the only trigger that may create one.                             */
IF OBJECT_ID('idx.DocumentIndexRecord') IS NULL
CREATE TABLE idx.DocumentIndexRecord (
    IndexRecordId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_DocumentIndexRecord PRIMARY KEY
                          CONSTRAINT DF_IdxRec_Id DEFAULT (NEWSEQUENTIALID()),
    DocumentId        UNIQUEIDENTIFIER NOT NULL,
    VersionId         UNIQUEIDENTIFIER NOT NULL,
    AclKeysJson       NVARCHAR(MAX)    NOT NULL,
    StatusCode        NVARCHAR(24)     NOT NULL,
    IsPrimaryResult   BIT              NOT NULL CONSTRAINT DF_IdxRec_Primary DEFAULT (1),
    ChunkCount        INT              NOT NULL CONSTRAINT DF_IdxRec_Chunks DEFAULT (0),
    EmbeddingRunId    UNIQUEIDENTIFIER NULL,
    ThumbnailRef      NVARCHAR(1000)   NULL,
    LanguageCode      NVARCHAR(8)      NULL,
    LastBuiltUtc      DATETIME2(3)     NOT NULL CONSTRAINT DF_IdxRec_Built DEFAULT (SYSUTCDATETIME()),
    LastAclRefreshUtc DATETIME2(3)     NULL,
    RemovedUtc        DATETIME2(3)     NULL,
    CONSTRAINT UQ_IndexRecord_Version UNIQUE (VersionId),
    CONSTRAINT FK_IdxRec_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_IdxRec_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_IdxRec_EmbRun   FOREIGN KEY (EmbeddingRunId)
        REFERENCES idx.EmbeddingRun(EmbeddingRunId),
    CONSTRAINT CK_IdxRec_Acl CHECK (ISJSON(AclKeysJson) = 1),
    /* HARD GUARANTEE: nothing but Published may be live in the index */
    CONSTRAINT CK_IdxRec_PublishedOnly CHECK (RemovedUtc IS NOT NULL OR StatusCode = N'Published')
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_IdxRec_Document' AND object_id = OBJECT_ID(N'idx.DocumentIndexRecord'))
CREATE NONCLUSTERED INDEX IX_IdxRec_Document ON idx.DocumentIndexRecord (DocumentId, IsPrimaryResult) INCLUDE (VersionId, LastBuiltUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_IdxRec_Live' AND object_id = OBJECT_ID(N'idx.DocumentIndexRecord'))
CREATE NONCLUSTERED INDEX IX_IdxRec_Live ON idx.DocumentIndexRecord (LastBuiltUtc DESC) WHERE RemovedUtc IS NULL;
GO

/*------------------------------------------------------------ idx.IndexChunk */
IF OBJECT_ID('idx.IndexChunk') IS NULL
CREATE TABLE idx.IndexChunk (
    ChunkId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndexChunk PRIMARY KEY,
    IndexRecordId UNIQUEIDENTIFIER NOT NULL,
    Ordinal       INT           NOT NULL,
    PageNumber    INT           NULL,
    CharStart     INT           NULL,
    CharEnd       INT           NULL,
    LanguageCode  NVARCHAR(8)   NULL,
    VectorWritten BIT           NOT NULL CONSTRAINT DF_Chunk_Vector DEFAULT (0),
    SearchDocKey  NVARCHAR(256) NULL,
    CONSTRAINT UQ_IndexChunk UNIQUE (IndexRecordId, Ordinal),
    CONSTRAINT FK_IndexChunk_Record FOREIGN KEY (IndexRecordId)
        REFERENCES idx.DocumentIndexRecord(IndexRecordId) ON DELETE CASCADE
);
GO

/*------------------------------------------------------------ idx.IndexQueue */
IF OBJECT_ID('idx.IndexQueue') IS NULL
CREATE TABLE idx.IndexQueue (
    QueueId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndexQueue PRIMARY KEY,
    DocumentId   UNIQUEIDENTIFIER NOT NULL,
    VersionId    UNIQUEIDENTIFIER NULL,
    Operation    NVARCHAR(32)  NOT NULL,
    Priority     INT           NOT NULL CONSTRAINT DF_IdxQ_Prio DEFAULT (100),
    Attempts     INT           NOT NULL CONSTRAINT DF_IdxQ_Attempts DEFAULT (0),
    LastError    NVARCHAR(MAX) NULL,
    EnqueuedUtc  DATETIME2(3)  NOT NULL CONSTRAINT DF_IdxQ_Enq DEFAULT (SYSUTCDATETIME()),
    ProcessedUtc DATETIME2(3)  NULL,
    CONSTRAINT FK_IdxQueue_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT CK_IdxQueue_Op CHECK (Operation IN
        (N'Upsert', N'RefreshAcl', N'Demote', N'Delete', N'Reembed'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_IndexQueue_Pending' AND object_id = OBJECT_ID(N'idx.IndexQueue'))
CREATE NONCLUSTERED INDEX IX_IndexQueue_Pending ON idx.IndexQueue (Priority, EnqueuedUtc)
    INCLUDE (DocumentId, VersionId, Operation, Attempts)
    WHERE ProcessedUtc IS NULL;
GO

/*-------------------------------------------------------- idx.IndexReconcile */
IF OBJECT_ID('idx.IndexReconcile') IS NULL
CREATE TABLE idx.IndexReconcile (
    ReconcileId    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndexReconcile PRIMARY KEY,
    RunUtc         DATETIME2(3)  NOT NULL CONSTRAINT DF_Recon_Utc DEFAULT (SYSUTCDATETIME()),
    RunType        NVARCHAR(24)  NOT NULL CONSTRAINT DF_Recon_Type DEFAULT (N'Scheduled'),
    RecordsChecked INT           NOT NULL CONSTRAINT DF_Recon_Check DEFAULT (0),
    DriftFound     INT           NOT NULL CONSTRAINT DF_Recon_Found DEFAULT (0),
    DriftRepaired  INT           NOT NULL CONSTRAINT DF_Recon_Fixed DEFAULT (0),
    OrphansRemoved INT           NOT NULL CONSTRAINT DF_Recon_Orph DEFAULT (0),
    DurationMs     INT           NULL,
    DetailJson     NVARCHAR(MAX) NULL,
    CONSTRAINT CK_Recon_Type CHECK (RunType IN (N'Scheduled', N'OnDemand', N'FullRebuild')),
    CONSTRAINT CK_Recon_Json CHECK (DetailJson IS NULL OR ISJSON(DetailJson) = 1)
);
GO

PRINT '07 · idx index projection schema ready.';
GO
