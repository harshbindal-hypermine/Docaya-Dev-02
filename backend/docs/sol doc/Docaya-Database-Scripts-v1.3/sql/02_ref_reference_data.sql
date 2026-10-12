/*==============================================================================
  02 · ref  ·  REFERENCE DATA AND CONTROLLED VOCABULARIES
  Admin-configured catalogues. Change on a governance cadence, not a
  transactional one. Seeded by configuration deployment (14_seed).
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*-------------------------------------------------- ref.Status (state machine) */
IF OBJECT_ID('ref.Status') IS NULL
CREATE TABLE ref.Status (
    StatusCode      NVARCHAR(24)  NOT NULL CONSTRAINT PK_ref_Status PRIMARY KEY,
    DisplayNameEn   NVARCHAR(64)  NOT NULL,
    DisplayNameAr   NVARCHAR(64)  NULL,
    IsStagingState  BIT           NOT NULL CONSTRAINT DF_Status_Stg  DEFAULT (0),
    IsPublished     BIT           NOT NULL CONSTRAINT DF_Status_Pub  DEFAULT (0),
    IsTerminal      BIT           NOT NULL CONSTRAINT DF_Status_Term DEFAULT (0),
    SortOrder       INT           NOT NULL CONSTRAINT DF_Status_Sort DEFAULT (0)
);
GO

/*----------------------------------- ref.StatusTransition (allowed moves only) */
IF OBJECT_ID('ref.StatusTransition') IS NULL
CREATE TABLE ref.StatusTransition (
    FromStatusCode  NVARCHAR(24) NOT NULL,
    ToStatusCode    NVARCHAR(24) NOT NULL,
    RequiresRole    NVARCHAR(48) NULL,
    Notes           NVARCHAR(256) NULL,
    CONSTRAINT PK_ref_StatusTransition PRIMARY KEY (FromStatusCode, ToStatusCode),
    CONSTRAINT FK_Trans_From FOREIGN KEY (FromStatusCode) REFERENCES ref.Status(StatusCode),
    CONSTRAINT FK_Trans_To   FOREIGN KEY (ToStatusCode)   REFERENCES ref.Status(StatusCode)
);
GO

/*----------------------------------------------------------- ref.DocumentClass */
IF OBJECT_ID('ref.DocumentClass') IS NULL
CREATE TABLE ref.DocumentClass (
    ClassId             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_DocumentClass PRIMARY KEY,
    ClassCode           NVARCHAR(32)  NOT NULL,
    DisplayNameEn       NVARCHAR(96)  NOT NULL,
    DisplayNameAr       NVARCHAR(96)  NULL,
    SharePointLibrary   NVARCHAR(128) NOT NULL,
    ContentTypeName     NVARCHAR(128) NULL,
    ThumbnailSuppressed BIT           NOT NULL CONSTRAINT DF_Class_Thumb DEFAULT (0),
    DefaultRetentionId  INT           NULL,
    IsActive            BIT           NOT NULL CONSTRAINT DF_Class_Active DEFAULT (1),
    CONSTRAINT UQ_ref_DocumentClass_Code UNIQUE (ClassCode)
);
GO

/*-------------------------------------------------------------- ref.Sensitivity */
IF OBJECT_ID('ref.Sensitivity') IS NULL
CREATE TABLE ref.Sensitivity (
    SensitivityId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_Sensitivity PRIMARY KEY,
    SensitivityCode     NVARCHAR(24) NOT NULL,
    DisplayNameEn       NVARCHAR(64) NOT NULL,
    DisplayNameAr       NVARCHAR(64) NULL,
    ClearanceRank       TINYINT      NOT NULL,
    RequiresClearance   BIT          NOT NULL CONSTRAINT DF_Sens_Clear DEFAULT (0),
    RequiresStepUpAuth  BIT          NOT NULL CONSTRAINT DF_Sens_Step  DEFAULT (0),
    PurviewLabelId      NVARCHAR(128) NULL,
    IsActive            BIT          NOT NULL CONSTRAINT DF_Sens_Active DEFAULT (1),
    CONSTRAINT UQ_ref_Sensitivity_Code UNIQUE (SensitivityCode),
    CONSTRAINT CK_ref_Sensitivity_Rank CHECK (ClearanceRank BETWEEN 1 AND 9)
);
GO

/*--------------------------------------------------------------- ref.Department */
IF OBJECT_ID('ref.Department') IS NULL
CREATE TABLE ref.Department (
    DepartmentId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_Department PRIMARY KEY,
    DepartmentCode      NVARCHAR(24)  NOT NULL,
    DisplayNameEn       NVARCHAR(128) NOT NULL,
    DisplayNameAr       NVARCHAR(128) NULL,
    ParentDepartmentId  INT           NULL,
    SharePointSiteUrl   NVARCHAR(400) NULL,
    SharePointSiteId    NVARCHAR(128) NULL,
    TermStoreGuid       UNIQUEIDENTIFIER NULL,
    IsActive            BIT           NOT NULL CONSTRAINT DF_Dept_Active DEFAULT (1),
    CONSTRAINT UQ_ref_Department_Code UNIQUE (DepartmentCode),
    CONSTRAINT FK_Department_Parent FOREIGN KEY (ParentDepartmentId)
        REFERENCES ref.Department(DepartmentId)
);
GO

/*------------------------------------------------------------------ ref.Standard */
IF OBJECT_ID('ref.Standard') IS NULL
CREATE TABLE ref.Standard (
    StandardId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_Standard PRIMARY KEY,
    StandardCode    NVARCHAR(32)  NOT NULL,
    DisplayNameEn   NVARCHAR(128) NOT NULL,
    DisplayNameAr   NVARCHAR(128) NULL,
    FolderSegment   NVARCHAR(64)  NOT NULL,
    TermStoreGuid   UNIQUEIDENTIFIER NULL,
    IsActive        BIT           NOT NULL CONSTRAINT DF_Std_Active DEFAULT (1),
    CONSTRAINT UQ_ref_Standard_Code UNIQUE (StandardCode)
);
GO

/*------------------------------------------------------------ ref.PublishingScope */
IF OBJECT_ID('ref.PublishingScope') IS NULL
CREATE TABLE ref.PublishingScope (
    ScopeId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_PublishingScope PRIMARY KEY,
    ScopeCode       NVARCHAR(32) NOT NULL,
    DisplayNameEn   NVARCHAR(96) NOT NULL,
    DisplayNameAr   NVARCHAR(96) NULL,
    BroadcastReach  NVARCHAR(32) NOT NULL,
    SortOrder       INT          NOT NULL CONSTRAINT DF_Scope_Sort DEFAULT (0),
    IsActive        BIT          NOT NULL CONSTRAINT DF_Scope_Active DEFAULT (1),
    CONSTRAINT UQ_ref_PublishingScope_Code UNIQUE (ScopeCode)
);
GO

/*------------------------------------------------------------------ ref.Priority */
IF OBJECT_ID('ref.Priority') IS NULL
CREATE TABLE ref.Priority (
    PriorityId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_Priority PRIMARY KEY,
    PriorityCode    NVARCHAR(24) NOT NULL,
    DisplayNameEn   NVARCHAR(64) NOT NULL,
    DisplayNameAr   NVARCHAR(64) NULL,
    RequestType     NVARCHAR(16) NOT NULL,
    QueueRank       INT          NOT NULL CONSTRAINT DF_Prio_Rank DEFAULT (0),
    IsActive        BIT          NOT NULL CONSTRAINT DF_Prio_Active DEFAULT (1),
    CONSTRAINT UQ_ref_Priority_Code UNIQUE (PriorityCode),
    CONSTRAINT CK_ref_Priority_ReqType CHECK (RequestType IN (N'Urgent', N'Normal'))
);
GO

/*------------------------------------------------------------- ref.RetentionPolicy */
IF OBJECT_ID('ref.RetentionPolicy') IS NULL
CREATE TABLE ref.RetentionPolicy (
    RetentionPolicyId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_RetentionPolicy PRIMARY KEY,
    PolicyCode        NVARCHAR(32)  NOT NULL,
    DisplayNameEn     NVARCHAR(128) NOT NULL,
    DisplayNameAr     NVARCHAR(128) NULL,
    TriggerType       NVARCHAR(24)  NOT NULL,
    TriggerEvent      NVARCHAR(64)  NULL,
    RetainMonths      INT           NOT NULL,
    DispositionAction NVARCHAR(24)  NOT NULL,
    RequiresApproval  BIT           NOT NULL CONSTRAINT DF_Ret_Appr DEFAULT (1),
    IsActive          BIT           NOT NULL CONSTRAINT DF_Ret_Active DEFAULT (1),
    CONSTRAINT UQ_ref_RetentionPolicy_Code UNIQUE (PolicyCode),
    CONSTRAINT CK_ref_Ret_Trigger CHECK (TriggerType IN (N'TimeBased', N'EventBased')),
    CONSTRAINT CK_ref_Ret_Action  CHECK (DispositionAction IN (N'Archive', N'ReviewThenDelete', N'Delete')),
    CONSTRAINT CK_ref_Ret_Months  CHECK (RetainMonths >= 0)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_DocumentClass_Retention')
    ALTER TABLE ref.DocumentClass ADD CONSTRAINT FK_DocumentClass_Retention
        FOREIGN KEY (DefaultRetentionId) REFERENCES ref.RetentionPolicy(RetentionPolicyId);
GO

/*------------------------------------- ref.MetadataSchema / ref.MetadataField */
IF OBJECT_ID('ref.MetadataSchema') IS NULL
CREATE TABLE ref.MetadataSchema (
    SchemaId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_MetadataSchema PRIMARY KEY,
    ClassId         INT           NOT NULL,
    VersionNo       INT           NOT NULL CONSTRAINT DF_Schema_Ver DEFAULT (1),
    EffectiveFromUtc DATETIME2(3) NOT NULL CONSTRAINT DF_Schema_Eff DEFAULT (SYSUTCDATETIME()),
    IsActive        BIT           NOT NULL CONSTRAINT DF_Schema_Active DEFAULT (1),
    PublishedBy     UNIQUEIDENTIFIER NULL,
    CONSTRAINT UQ_ref_MetadataSchema UNIQUE (ClassId, VersionNo),
    CONSTRAINT FK_MetadataSchema_Class FOREIGN KEY (ClassId)
        REFERENCES ref.DocumentClass(ClassId)
);
GO

IF OBJECT_ID('ref.MetadataField') IS NULL
CREATE TABLE ref.MetadataField (
    FieldId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_MetadataField PRIMARY KEY,
    SchemaId        INT           NOT NULL,
    FieldKey        NVARCHAR(64)  NOT NULL,
    DisplayNameEn   NVARCHAR(128) NOT NULL,
    DisplayNameAr   NVARCHAR(128) NULL,
    DataType        NVARCHAR(24)  NOT NULL,
    IsRequired      BIT           NOT NULL CONSTRAINT DF_Field_Req DEFAULT (0),
    MaxLength       INT           NULL,
    RegexPattern    NVARCHAR(256) NULL,
    ChoiceListJson  NVARCHAR(MAX) NULL,
    SharePointColumn NVARCHAR(128) NULL,
    SearchFieldName NVARCHAR(128) NULL,
    SortOrder       INT           NOT NULL CONSTRAINT DF_Field_Sort DEFAULT (0),
    CONSTRAINT UQ_ref_MetadataField UNIQUE (SchemaId, FieldKey),
    CONSTRAINT FK_MetadataField_Schema FOREIGN KEY (SchemaId)
        REFERENCES ref.MetadataSchema(SchemaId),
    CONSTRAINT CK_ref_Field_Type CHECK (DataType IN
        (N'Text', N'Number', N'Date', N'Choice', N'Person', N'Boolean'))
);
GO

/*------------------------------------------------------------ ref.HolidayCalendar
  Versioned non-working days. Amending the calendar creates a NEW VersionNo. */
IF OBJECT_ID('ref.HolidayCalendar') IS NULL
CREATE TABLE ref.HolidayCalendar (
    CalendarId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_HolidayCalendar PRIMARY KEY,
    CalendarCode    NVARCHAR(24) NOT NULL,
    VersionNo       INT          NOT NULL,
    HolidayDate     DATE         NOT NULL,
    DescriptionEn   NVARCHAR(128) NULL,
    DescriptionAr   NVARCHAR(128) NULL,
    CONSTRAINT UQ_ref_HolidayCalendar UNIQUE (CalendarCode, VersionNo, HolidayDate)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Holiday_Lookup' AND object_id = OBJECT_ID(N'ref.HolidayCalendar'))
CREATE NONCLUSTERED INDEX IX_Holiday_Lookup ON ref.HolidayCalendar (CalendarCode, VersionNo, HolidayDate);
GO

/*---------------------------------------------------------- ref.WorkingWeek */
IF OBJECT_ID('ref.WorkingWeek') IS NULL
CREATE TABLE ref.WorkingWeek (
    CalendarCode    NVARCHAR(24) NOT NULL,
    VersionNo       INT          NOT NULL,
    DayOfWeekNo     TINYINT      NOT NULL,
    IsWorkingDay    BIT          NOT NULL,
    CONSTRAINT PK_ref_WorkingWeek PRIMARY KEY (CalendarCode, VersionNo, DayOfWeekNo),
    CONSTRAINT CK_ref_WorkingWeek_Day CHECK (DayOfWeekNo BETWEEN 1 AND 7)
);
GO

/*------------------------------------------------------------- ref.SlaTarget */
IF OBJECT_ID('ref.SlaTarget') IS NULL
CREATE TABLE ref.SlaTarget (
    SlaTargetId       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ref_SlaTarget PRIMARY KEY,
    ScopeType         NVARCHAR(24) NOT NULL,
    ScopeId           INT          NULL,
    RequestType       NVARCHAR(16) NOT NULL,
    TargetWorkingDays INT          NOT NULL,
    AtRiskWindowDays  INT          NOT NULL CONSTRAINT DF_Sla_Warn DEFAULT (3),
    CalendarCode      NVARCHAR(24) NOT NULL CONSTRAINT DF_Sla_Cal DEFAULT (N'UAE-FED'),
    IsActive          BIT          NOT NULL CONSTRAINT DF_Sla_Active DEFAULT (1),
    CONSTRAINT CK_ref_Sla_ReqType CHECK (RequestType IN (N'Urgent', N'Normal')),
    CONSTRAINT CK_ref_Sla_Scope   CHECK (ScopeType IN (N'Global', N'Class', N'Department')),
    CONSTRAINT CK_ref_Sla_Days    CHECK (TargetWorkingDays > 0 AND AtRiskWindowDays >= 0)
);
GO

PRINT '02 · ref schema ready.';
GO
