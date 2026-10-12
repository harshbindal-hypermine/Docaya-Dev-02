/*==============================================================================
  04 · docaya  ·  CORE DOCUMENT REGISTRY   (SYSTEM OF RECORD FOR METADATA)
  The only schema authoritative for business metadata. Every other schema
  either points at it or is derived from it.               TAD 11.5
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*--------------------------------------------------------- docaya.Document
  The anchor of chain of custody. A row exists from the instant a tracking
  number is issued.                                                          */
IF OBJECT_ID('docaya.Document') IS NULL
CREATE TABLE docaya.Document (
    DocumentId           UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_Document PRIMARY KEY
                             CONSTRAINT DF_Document_Id DEFAULT (NEWSEQUENTIALID()),
    TrackingNumber       NVARCHAR(20)     NOT NULL,
    StatusCode           NVARCHAR(24)     NOT NULL,
    ClassId              INT              NOT NULL,
    SensitivityId        INT              NOT NULL,
    DepartmentId         INT              NOT NULL,
    StandardId           INT              NULL,
    PublishingScopeId    INT              NOT NULL,
    PriorityId           INT              NOT NULL,
    BusinessTitle        NVARCHAR(400)    NOT NULL,
    BusinessTitleAr      NVARCHAR(400)    NULL,
    Description          NVARCHAR(MAX)    NULL,
    Keywords             NVARCHAR(1000)   NULL,
    ExternalReference    NVARCHAR(128)    NULL,
    OwnerPrincipalId     UNIQUEIDENTIFIER NOT NULL,
    CurrentVersionId     UNIQUEIDENTIFIER NULL,
    ExpiryUtc            DATE             NULL,
    RetentionPolicyId    INT              NULL,
    DispositionDueUtc    DATE             NULL,
    LegalHoldFlag        BIT              NOT NULL CONSTRAINT DF_Doc_Hold DEFAULT (0),
    DetectedLanguage     NVARCHAR(8)      NULL,
    RowVersion           ROWVERSION       NOT NULL,
    CreatedUtc           DATETIME2(3)     NOT NULL CONSTRAINT DF_Doc_Created DEFAULT (SYSUTCDATETIME()),
    CreatedByPrincipalId UNIQUEIDENTIFIER NOT NULL,
    ModifiedUtc          DATETIME2(3)     NULL,
    ModifiedByPrincipalId UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_Document_Tracking UNIQUE (TrackingNumber),
    CONSTRAINT FK_Document_Status   FOREIGN KEY (StatusCode)        REFERENCES ref.Status(StatusCode),
    CONSTRAINT FK_Document_Class    FOREIGN KEY (ClassId)           REFERENCES ref.DocumentClass(ClassId),
    CONSTRAINT FK_Document_Sens     FOREIGN KEY (SensitivityId)     REFERENCES ref.Sensitivity(SensitivityId),
    CONSTRAINT FK_Document_Dept     FOREIGN KEY (DepartmentId)      REFERENCES ref.Department(DepartmentId),
    CONSTRAINT FK_Document_Standard FOREIGN KEY (StandardId)        REFERENCES ref.Standard(StandardId),
    CONSTRAINT FK_Document_Scope    FOREIGN KEY (PublishingScopeId) REFERENCES ref.PublishingScope(ScopeId),
    CONSTRAINT FK_Document_Priority FOREIGN KEY (PriorityId)        REFERENCES ref.Priority(PriorityId),
    CONSTRAINT FK_Document_Owner    FOREIGN KEY (OwnerPrincipalId)  REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Document_Creator  FOREIGN KEY (CreatedByPrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Document_Retention FOREIGN KEY (RetentionPolicyId)
        REFERENCES ref.RetentionPolicy(RetentionPolicyId),
    CONSTRAINT CK_Document_Tracking CHECK (TrackingNumber LIKE N'DOC-[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]')
);
GO

/*----------------------------------------------------- docaya.DocumentVersion
  One row per APPROVED version. Carries SharePoint coordinates and integrity
  evidence; written only after the hash comparison succeeds.                 */
IF OBJECT_ID('docaya.DocumentVersion') IS NULL
CREATE TABLE docaya.DocumentVersion (
    VersionId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_DocumentVersion PRIMARY KEY
                             CONSTRAINT DF_Version_Id DEFAULT (NEWSEQUENTIALID()),
    DocumentId           UNIQUEIDENTIFIER NOT NULL,
    VersionLabel         NVARCHAR(20)     NOT NULL,
    VersionSequence      INT              NOT NULL,
    SpSiteId             NVARCHAR(128)    NULL,
    SpDriveId            NVARCHAR(128)    NULL,
    SpItemId             NVARCHAR(128)    NULL,
    SpWebUrl             NVARCHAR(1000)   NULL,
    SpVersionLabel       NVARCHAR(20)     NULL,
    ContentHashSha256    BINARY(32)       NOT NULL,
    SizeBytes            BIGINT           NOT NULL,
    MimeType             NVARCHAR(128)    NULL,
    PageCount            INT              NULL,
    ThumbnailRef         NVARCHAR(1000)   NULL,
    PublishedUtc         DATETIME2(3)     NULL,
    PublishedByPrincipalId UNIQUEIDENTIFIER NULL,
    SupersededByVersionId  UNIQUEIDENTIFIER NULL,
    SupersededUtc        DATETIME2(3)     NULL,
    IsCurrent            BIT              NOT NULL CONSTRAINT DF_Version_Current DEFAULT (0),
    CONSTRAINT UQ_DocumentVersion_Label UNIQUE (DocumentId, VersionLabel),
    CONSTRAINT UQ_DocumentVersion_Seq   UNIQUE (DocumentId, VersionSequence),
    CONSTRAINT FK_Version_Document FOREIGN KEY (DocumentId)
        REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Version_Superseded FOREIGN KEY (SupersededByVersionId)
        REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_Version_PublishedBy FOREIGN KEY (PublishedByPrincipalId)
        REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_Version_Size CHECK (SizeBytes > 0 AND SizeBytes <= 104857600)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Document_CurrentVersion')
    ALTER TABLE docaya.Document ADD CONSTRAINT FK_Document_CurrentVersion
        FOREIGN KEY (CurrentVersionId) REFERENCES docaya.DocumentVersion(VersionId);
GO

/*--------------------------------------------------- docaya.DocumentMetadata */
IF OBJECT_ID('docaya.DocumentMetadata') IS NULL
CREATE TABLE docaya.DocumentMetadata (
    MetadataId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DocumentMetadata PRIMARY KEY,
    DocumentId       UNIQUEIDENTIFIER NOT NULL,
    VersionId        UNIQUEIDENTIFIER NULL,
    SchemaId         INT              NOT NULL,
    FieldKey         NVARCHAR(64)     NOT NULL,
    FieldValue       NVARCHAR(MAX)    NULL,
    EffectiveFromUtc DATETIME2(3)     NOT NULL CONSTRAINT DF_Meta_From DEFAULT (SYSUTCDATETIME()),
    EffectiveToUtc   DATETIME2(3)     NULL,
    ActorPrincipalId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT FK_Metadata_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Metadata_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT FK_Metadata_Schema   FOREIGN KEY (SchemaId)   REFERENCES ref.MetadataSchema(SchemaId),
    CONSTRAINT FK_Metadata_Actor    FOREIGN KEY (ActorPrincipalId) REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Metadata_Doc_Field' AND object_id = OBJECT_ID(N'docaya.DocumentMetadata'))
CREATE NONCLUSTERED INDEX IX_Metadata_Doc_Field ON docaya.DocumentMetadata (DocumentId, FieldKey, EffectiveFromUtc DESC)
    INCLUDE (FieldValue, EffectiveToUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Metadata_Current' AND object_id = OBJECT_ID(N'docaya.DocumentMetadata'))
CREATE NONCLUSTERED INDEX IX_Metadata_Current ON docaya.DocumentMetadata (DocumentId, FieldKey)
    INCLUDE (FieldValue) WHERE EffectiveToUtc IS NULL;
GO

/*-------------------------------------------------------- docaya.DocumentTag */
IF OBJECT_ID('docaya.DocumentTag') IS NULL
CREATE TABLE docaya.DocumentTag (
    TagId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DocumentTag PRIMARY KEY,
    DocumentId   UNIQUEIDENTIFIER NOT NULL,
    DepartmentId INT              NOT NULL,
    IsOwning     BIT              NOT NULL CONSTRAINT DF_Tag_Owning DEFAULT (0),
    AddedUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_Tag_Added DEFAULT (SYSUTCDATETIME()),
    AddedBy      UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_DocumentTag UNIQUE (DocumentId, DepartmentId),
    CONSTRAINT FK_Tag_Document   FOREIGN KEY (DocumentId)   REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Tag_Department FOREIGN KEY (DepartmentId) REFERENCES ref.Department(DepartmentId),
    CONSTRAINT FK_Tag_AddedBy    FOREIGN KEY (AddedBy)      REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_DocumentTag_Owning' AND object_id = OBJECT_ID(N'docaya.DocumentTag'))
CREATE UNIQUE NONCLUSTERED INDEX UX_DocumentTag_Owning ON docaya.DocumentTag (DocumentId) WHERE IsOwning = 1;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_DocumentTag_Department' AND object_id = OBJECT_ID(N'docaya.DocumentTag'))
CREATE NONCLUSTERED INDEX IX_DocumentTag_Department ON docaya.DocumentTag (DepartmentId) INCLUDE (DocumentId, IsOwning);
GO

/*-------------------------------------------------- docaya.DocumentThumbnail */
IF OBJECT_ID('docaya.DocumentThumbnail') IS NULL
CREATE TABLE docaya.DocumentThumbnail (
    ThumbnailId  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DocumentThumbnail PRIMARY KEY,
    DocumentId   UNIQUEIDENTIFIER NOT NULL,
    VersionId    UNIQUEIDENTIFIER NULL,
    BlobUri      NVARCHAR(1000)   NOT NULL,
    WidthPx      INT              NULL,
    HeightPx     INT              NULL,
    Suppressed   BIT              NOT NULL CONSTRAINT DF_Thumb_Supp DEFAULT (0),
    GeneratedUtc DATETIME2(3)     NOT NULL CONSTRAINT DF_Thumb_Gen DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Thumb_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Thumb_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Thumbnail_Doc_Version' AND object_id = OBJECT_ID(N'docaya.DocumentThumbnail'))
CREATE NONCLUSTERED INDEX IX_Thumbnail_Doc_Version ON docaya.DocumentThumbnail (DocumentId, VersionId) INCLUDE (BlobUri, Suppressed);
GO

/*--------------------------------------------------- docaya.DocumentRelation */
IF OBJECT_ID('docaya.DocumentRelation') IS NULL
CREATE TABLE docaya.DocumentRelation (
    RelationId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DocumentRelation PRIMARY KEY,
    FromDocumentId UNIQUEIDENTIFIER NOT NULL,
    ToDocumentId   UNIQUEIDENTIFIER NOT NULL,
    RelationType   NVARCHAR(32)     NOT NULL,
    CreatedUtc     DATETIME2(3)     NOT NULL CONSTRAINT DF_Rel_Created DEFAULT (SYSUTCDATETIME()),
    CreatedBy      UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_DocumentRelation UNIQUE (FromDocumentId, ToDocumentId, RelationType),
    CONSTRAINT FK_Relation_From FOREIGN KEY (FromDocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Relation_To   FOREIGN KEY (ToDocumentId)   REFERENCES docaya.Document(DocumentId),
    CONSTRAINT CK_Relation_NotSelf CHECK (FromDocumentId <> ToDocumentId),
    CONSTRAINT CK_Relation_Type CHECK (RelationType IN
        (N'ReplyTo', N'Supersedes', N'RelatedTo', N'Attachment'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Relation_To' AND object_id = OBJECT_ID(N'docaya.DocumentRelation'))
CREATE NONCLUSTERED INDEX IX_Relation_To ON docaya.DocumentRelation (ToDocumentId, RelationType);
GO

/*----------------------------------------------------- docaya.Correspondence */
IF OBJECT_ID('docaya.Correspondence') IS NULL
CREATE TABLE docaya.Correspondence (
    DocumentId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_Correspondence PRIMARY KEY,
    ReferenceNumber NVARCHAR(64)  NOT NULL,
    Direction       NVARCHAR(16)  NOT NULL,
    SenderName      NVARCHAR(256) NULL,
    RecipientName   NVARCHAR(256) NULL,
    SubjectEn       NVARCHAR(400) NULL,
    SubjectAr       NVARCHAR(400) NULL,
    DueUtc          DATE          NULL,
    AcknowledgedUtc DATETIME2(3)  NULL,
    CONSTRAINT UQ_Correspondence_Ref UNIQUE (ReferenceNumber),
    CONSTRAINT FK_Correspondence_Document FOREIGN KEY (DocumentId)
        REFERENCES docaya.Document(DocumentId),
    CONSTRAINT CK_Correspondence_Dir CHECK (Direction IN (N'Incoming', N'Outgoing'))
);
GO

/*----------------------------------------------------------- docaya.LegalHold */
IF OBJECT_ID('docaya.LegalHold') IS NULL
CREATE TABLE docaya.LegalHold (
    LegalHoldId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LegalHold PRIMARY KEY,
    DocumentId    UNIQUEIDENTIFIER NOT NULL,
    HoldReference NVARCHAR(64)  NOT NULL,
    Reason        NVARCHAR(1000) NOT NULL,
    AppliedUtc    DATETIME2(3)  NOT NULL CONSTRAINT DF_Hold_Applied DEFAULT (SYSUTCDATETIME()),
    AppliedBy     UNIQUEIDENTIFIER NOT NULL,
    ReleasedUtc   DATETIME2(3)  NULL,
    ReleasedBy    UNIQUEIDENTIFIER NULL,
    ReleaseReason NVARCHAR(1000) NULL,
    CONSTRAINT FK_Hold_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Hold_AppliedBy FOREIGN KEY (AppliedBy) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Hold_ReleasedBy FOREIGN KEY (ReleasedBy) REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_LegalHold_Active' AND object_id = OBJECT_ID(N'docaya.LegalHold'))
CREATE UNIQUE NONCLUSTERED INDEX UX_LegalHold_Active ON docaya.LegalHold (DocumentId) WHERE ReleasedUtc IS NULL;
GO

/*------------------------------------------------- docaya.Document · INDEXES */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_Dept_Status' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_Dept_Status ON docaya.Document (DepartmentId, StatusCode)
    INCLUDE (TrackingNumber, BusinessTitle, StandardId, SensitivityId,
             OwnerPrincipalId, CurrentVersionId, CreatedUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_Expiry' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_Expiry ON docaya.Document (ExpiryUtc)
    INCLUDE (TrackingNumber, OwnerPrincipalId, DepartmentId)
    WHERE ExpiryUtc IS NOT NULL AND LegalHoldFlag = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_DispositionDue' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_DispositionDue ON docaya.Document (DispositionDueUtc)
    INCLUDE (RetentionPolicyId, StatusCode)
    WHERE DispositionDueUtc IS NOT NULL AND LegalHoldFlag = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_Owner_Status' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_Owner_Status ON docaya.Document (OwnerPrincipalId, StatusCode)
    INCLUDE (TrackingNumber, BusinessTitle, ModifiedUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_Standard_Status' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_Standard_Status ON docaya.Document (StandardId, StatusCode)
    INCLUDE (DepartmentId, TrackingNumber) WHERE StandardId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Document_Published' AND object_id = OBJECT_ID(N'docaya.Document'))
CREATE NONCLUSTERED INDEX IX_Document_Published ON docaya.Document (StatusCode, ModifiedUtc DESC)
    INCLUDE (DocumentId, CurrentVersionId) WHERE StatusCode = N'Published';
GO

PRINT '04 · docaya core registry ready.';
GO
