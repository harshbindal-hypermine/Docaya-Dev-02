/*==============================================================================
  05 · stg  ·  STAGING AND UPLOAD PROCESSING   (TRANSIENT · PURGEABLE)
  Rows are transient and purgeable on a lifecycle independent of the permanent
  registry. The capture worker's principal is granted on stg ONLY, so a
  compromise cannot read or alter the registry, workflow or audit.  TAD 11.4
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*-------------------------------------------------------- stg.UploadSession
  Exactly ONE file per registration, maximum 100 MB (FR-CAP-01 / FR-CAP-02). */
IF OBJECT_ID('stg.UploadSession') IS NULL
CREATE TABLE stg.UploadSession (
    SessionId        UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_UploadSession PRIMARY KEY
                         CONSTRAINT DF_Session_Id DEFAULT (NEWSEQUENTIALID()),
    DocumentId       UNIQUEIDENTIFIER NOT NULL,
    OriginalFileName NVARCHAR(400)    NOT NULL,
    DeclaredMimeType NVARCHAR(128)    NULL,
    TotalBytes       BIGINT           NOT NULL,
    ChunkSizeBytes   INT              NOT NULL CONSTRAINT DF_Session_Chunk DEFAULT (4194304),
    ReceivedBytes    BIGINT           NOT NULL CONSTRAINT DF_Session_Recv DEFAULT (0),
    StateCode        NVARCHAR(24)     NOT NULL CONSTRAINT DF_Session_State DEFAULT (N'Open'),
    CreatedUtc       DATETIME2(3)     NOT NULL CONSTRAINT DF_Session_Created DEFAULT (SYSUTCDATETIME()),
    ExpiresUtc       DATETIME2(3)     NOT NULL,
    CommittedUtc     DATETIME2(3)     NULL,
    CreatedBy        UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT CK_Session_State CHECK (StateCode IN (N'Open', N'Committed', N'Aborted', N'Expired')),
    CONSTRAINT CK_Session_Size  CHECK (TotalBytes > 0 AND TotalBytes <= 104857600),
    CONSTRAINT CK_Session_Recv  CHECK (ReceivedBytes >= 0 AND ReceivedBytes <= TotalBytes)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_UploadSession_OpenPerDoc' AND object_id = OBJECT_ID(N'stg.UploadSession'))
CREATE UNIQUE NONCLUSTERED INDEX UX_UploadSession_OpenPerDoc ON stg.UploadSession (DocumentId) WHERE StateCode = N'Open';
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_UploadSession_Expiry' AND object_id = OBJECT_ID(N'stg.UploadSession'))
CREATE NONCLUSTERED INDEX IX_UploadSession_Expiry ON stg.UploadSession (ExpiresUtc) WHERE StateCode = N'Open';
GO

/*------------------------------------------------------------ stg.FileChunk */
IF OBJECT_ID('stg.FileChunk') IS NULL
CREATE TABLE stg.FileChunk (
    ChunkId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FileChunk PRIMARY KEY,
    SessionId   UNIQUEIDENTIFIER NOT NULL,
    Ordinal     INT              NOT NULL,
    ByteStart   BIGINT           NOT NULL,
    ByteEnd     BIGINT           NOT NULL,
    ChunkHash   BINARY(32)       NULL,
    ReceivedUtc DATETIME2(3)     NOT NULL CONSTRAINT DF_Chunk_Recv DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_FileChunk UNIQUE (SessionId, Ordinal),
    CONSTRAINT FK_Chunk_Session FOREIGN KEY (SessionId)
        REFERENCES stg.UploadSession(SessionId) ON DELETE CASCADE,
    CONSTRAINT CK_Chunk_Range CHECK (ByteEnd >= ByteStart AND ByteStart >= 0)
);
GO

/*------------------------------------------------------------ stg.StagedFile
  The committed unchanged original. This byte stream is the byte stream that
  will be published, verified by hash comparison.                            */
IF OBJECT_ID('stg.StagedFile') IS NULL
CREATE TABLE stg.StagedFile (
    StagedFileId    UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_StagedFile PRIMARY KEY
                        CONSTRAINT DF_Staged_Id DEFAULT (NEWSEQUENTIALID()),
    DocumentId      UNIQUEIDENTIFIER NOT NULL,
    SessionId       UNIQUEIDENTIFIER NULL,
    BlobUri         NVARCHAR(1000)   NOT NULL,
    BlobContainer   NVARCHAR(128)    NOT NULL,
    SizeBytes       BIGINT           NOT NULL,
    MimeDetected    NVARCHAR(128)    NOT NULL,
    FileExtension   NVARCHAR(16)     NULL,
    Sha256          BINARY(32)       NOT NULL,
    CommittedUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_Staged_Commit DEFAULT (SYSUTCDATETIME()),
    ReconciledUtc   DATETIME2(3)     NULL,
    ReconcileAction NVARCHAR(24)     NULL,
    CONSTRAINT FK_Staged_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Staged_Session  FOREIGN KEY (SessionId)  REFERENCES stg.UploadSession(SessionId),
    CONSTRAINT CK_Staged_Size CHECK (SizeBytes > 0 AND SizeBytes <= 104857600),
    CONSTRAINT CK_Staged_Action CHECK (ReconcileAction IS NULL
        OR ReconcileAction IN (N'Purged', N'Retained', N'Moved'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_StagedFile_Document' AND object_id = OBJECT_ID(N'stg.StagedFile'))
CREATE NONCLUSTERED INDEX IX_StagedFile_Document ON stg.StagedFile (DocumentId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_StagedFile_Hash' AND object_id = OBJECT_ID(N'stg.StagedFile'))
CREATE NONCLUSTERED INDEX IX_StagedFile_Hash ON stg.StagedFile (Sha256) INCLUDE (DocumentId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_StagedFile_Unreconciled' AND object_id = OBJECT_ID(N'stg.StagedFile'))
CREATE NONCLUSTERED INDEX IX_StagedFile_Unreconciled ON stg.StagedFile (CommittedUtc) WHERE ReconciledUtc IS NULL;
GO

/*------------------------------------------------------------ stg.ScanResult
  Progression is BLOCKED until a clean verdict.                              */
IF OBJECT_ID('stg.ScanResult') IS NULL
CREATE TABLE stg.ScanResult (
    ScanId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ScanResult PRIMARY KEY,
    StagedFileId UNIQUEIDENTIFIER NOT NULL,
    ScanType     NVARCHAR(24)  NOT NULL,
    Engine       NVARCHAR(64)  NULL,
    Verdict      NVARCHAR(16)  NOT NULL,
    DetailJson   NVARCHAR(MAX) NULL,
    ScannedUtc   DATETIME2(3)  NOT NULL CONSTRAINT DF_Scan_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Scan_StagedFile FOREIGN KEY (StagedFileId)
        REFERENCES stg.StagedFile(StagedFileId),
    CONSTRAINT CK_Scan_Verdict CHECK (Verdict IN (N'Clean', N'Infected', N'Blocked', N'Error')),
    CONSTRAINT CK_Scan_Type    CHECK (ScanType IN (N'Malware', N'DLP', N'SignatureCheck')),
    CONSTRAINT CK_Scan_Json    CHECK (DetailJson IS NULL OR ISJSON(DetailJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Scan_File_Type' AND object_id = OBJECT_ID(N'stg.ScanResult'))
CREATE NONCLUSTERED INDEX IX_Scan_File_Type ON stg.ScanResult (StagedFileId, ScanType, ScannedUtc DESC) INCLUDE (Verdict);
GO

/*------------------------------------------------------ stg.ExtractionResult
  Basic machine-readable text only. NOT classification: no AI, no metadata
  suggestion, no approver recommendation.                    TAD 7.1         */
IF OBJECT_ID('stg.ExtractionResult') IS NULL
CREATE TABLE stg.ExtractionResult (
    ExtractionId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ExtractionResult PRIMARY KEY,
    StagedFileId      UNIQUEIDENTIFIER NOT NULL,
    LanguageCode      NVARCHAR(8)   NULL,
    PageCount         INT           NULL,
    CharacterCount    BIGINT        NULL,
    TextUri           NVARCHAR(1000) NULL,
    ExtractionQuality NVARCHAR(16)  NULL,
    ExtractedUtc      DATETIME2(3)  NOT NULL CONSTRAINT DF_Extract_Utc DEFAULT (SYSUTCDATETIME()),
    PurgedUtc         DATETIME2(3)  NULL,
    CONSTRAINT FK_Extract_StagedFile FOREIGN KEY (StagedFileId)
        REFERENCES stg.StagedFile(StagedFileId),
    CONSTRAINT CK_Extract_Quality CHECK (ExtractionQuality IS NULL
        OR ExtractionQuality IN (N'Good', N'Partial', N'Poor'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Extraction_File' AND object_id = OBJECT_ID(N'stg.ExtractionResult'))
CREATE NONCLUSTERED INDEX IX_Extraction_File ON stg.ExtractionResult (StagedFileId);
GO

/*------------------------------------------------------- stg.ThumbnailAsset */
IF OBJECT_ID('stg.ThumbnailAsset') IS NULL
CREATE TABLE stg.ThumbnailAsset (
    ThumbId          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ThumbnailAsset PRIMARY KEY,
    DocumentId       UNIQUEIDENTIFIER NOT NULL,
    StagedFileId     UNIQUEIDENTIFIER NULL,
    VersionLabel     NVARCHAR(20)   NULL,
    BlobUri          NVARCHAR(1000) NOT NULL,
    WidthPx          INT            NULL,
    HeightPx         INT            NULL,
    GenerationStatus NVARCHAR(16)   NOT NULL CONSTRAINT DF_Thumb_Status DEFAULT (N'Generated'),
    GeneratedUtc     DATETIME2(3)   NOT NULL CONSTRAINT DF_ThumbAsset_Utc DEFAULT (SYSUTCDATETIME()),
    PromotedUtc      DATETIME2(3)   NULL,
    CONSTRAINT FK_ThumbAsset_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_ThumbAsset_StagedFile FOREIGN KEY (StagedFileId)
        REFERENCES stg.StagedFile(StagedFileId),
    CONSTRAINT CK_ThumbAsset_Status CHECK (GenerationStatus IN
        (N'Generated', N'Fallback', N'Suppressed', N'Failed'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ThumbAsset_Document' AND object_id = OBJECT_ID(N'stg.ThumbnailAsset'))
CREATE NONCLUSTERED INDEX IX_ThumbAsset_Document ON stg.ThumbnailAsset (DocumentId, GeneratedUtc DESC);
GO

PRINT '05 · stg staging schema ready.';
GO
