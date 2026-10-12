/*==============================================================================
  08 · ntf  ·  NOTIFICATION HISTORY AND PREFERENCES
  Large, append-heavy and separately prunable; keeps delivery detail out of
  the registry.                                             TAD 11.9 / 25.1
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*--------------------------------------------------- ntf.NotificationType */
IF OBJECT_ID('ntf.NotificationType') IS NULL
CREATE TABLE ntf.NotificationType (
    TypeCode          NVARCHAR(48)  NOT NULL CONSTRAINT PK_NotificationType PRIMARY KEY,
    CategoryCode      NVARCHAR(32)  NOT NULL,
    DisplayNameEn     NVARCHAR(128) NOT NULL,
    DisplayNameAr     NVARCHAR(128) NULL,
    DefaultChannels   NVARCHAR(128) NOT NULL,
    IsMandatory       BIT NOT NULL CONSTRAINT DF_NtfType_Mand DEFAULT (0),
    RespectQuietHours BIT NOT NULL CONSTRAINT DF_NtfType_Quiet DEFAULT (1),
    IsActive          BIT NOT NULL CONSTRAINT DF_NtfType_Active DEFAULT (1)
);
GO

/*----------------------------------------------------------- ntf.Notification */
IF OBJECT_ID('ntf.Notification') IS NULL
CREATE TABLE ntf.Notification (
    NotificationId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Notification PRIMARY KEY,
    DocumentId           UNIQUEIDENTIFIER NULL,
    WorkflowInstanceId   UNIQUEIDENTIFIER NULL,
    RecipientPrincipalId UNIQUEIDENTIFIER NOT NULL,
    TypeCode             NVARCHAR(48)   NOT NULL,
    ChannelCode          NVARCHAR(16)   NOT NULL,
    SubjectEn            NVARCHAR(400)  NULL,
    SubjectAr            NVARCHAR(400)  NULL,
    BodyPreview          NVARCHAR(1000) NULL,
    DedupKey             NVARCHAR(200)  NOT NULL,
    BroadcastId          BIGINT         NULL,
    CreatedUtc           DATETIME2(3)   NOT NULL CONSTRAINT DF_Ntf_Created DEFAULT (SYSUTCDATETIME()),
    SentUtc              DATETIME2(3)   NULL,
    ReadUtc              DATETIME2(3)   NULL,
    CONSTRAINT FK_Ntf_Recipient FOREIGN KEY (RecipientPrincipalId)
        REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Ntf_Type     FOREIGN KEY (TypeCode)   REFERENCES ntf.NotificationType(TypeCode),
    CONSTRAINT FK_Ntf_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Ntf_Instance FOREIGN KEY (WorkflowInstanceId)
        REFERENCES wf.WorkflowInstance(WorkflowInstanceId),
    CONSTRAINT CK_Ntf_Channel CHECK (ChannelCode IN (N'InApp', N'Email', N'Teams', N'Push'))
);
GO
/* EXACTLY ONE alert per entitled recipient per event (FR-PUB-09) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Notification_Dedup' AND object_id = OBJECT_ID(N'ntf.Notification'))
CREATE UNIQUE NONCLUSTERED INDEX UX_Notification_Dedup ON ntf.Notification (RecipientPrincipalId, DedupKey, ChannelCode);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Notification_Unread' AND object_id = OBJECT_ID(N'ntf.Notification'))
CREATE NONCLUSTERED INDEX IX_Notification_Unread ON ntf.Notification (RecipientPrincipalId, CreatedUtc DESC)
    INCLUDE (TypeCode, DocumentId, SubjectEn) WHERE ReadUtc IS NULL;
GO

/*------------------------------------------------- ntf.NotificationPreference */
IF OBJECT_ID('ntf.NotificationPreference') IS NULL
CREATE TABLE ntf.NotificationPreference (
    PreferenceId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_NotificationPreference PRIMARY KEY,
    PrincipalId    UNIQUEIDENTIFIER NOT NULL,
    TypeCode       NVARCHAR(48) NOT NULL,
    ChannelCode    NVARCHAR(16) NOT NULL,
    Enabled        BIT          NOT NULL CONSTRAINT DF_Pref_Enabled DEFAULT (1),
    QuietFromLocal TIME(0)      NULL,
    QuietToLocal   TIME(0)      NULL,
    TimeZoneId     NVARCHAR(64) NULL,
    CONSTRAINT UQ_NotificationPreference UNIQUE (PrincipalId, TypeCode, ChannelCode),
    CONSTRAINT FK_Pref_Principal FOREIGN KEY (PrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Pref_Type      FOREIGN KEY (TypeCode)    REFERENCES ntf.NotificationType(TypeCode),
    CONSTRAINT CK_Pref_Channel CHECK (ChannelCode IN (N'InApp', N'Email', N'Teams', N'Push'))
);
GO

/*---------------------------------------------------- ntf.BroadcastAudience */
IF OBJECT_ID('ntf.BroadcastAudience') IS NULL
CREATE TABLE ntf.BroadcastAudience (
    BroadcastId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BroadcastAudience PRIMARY KEY,
    DocumentId        UNIQUEIDENTIFIER NOT NULL,
    VersionId         UNIQUEIDENTIFIER NULL,
    ScopeCode         NVARCHAR(32)  NOT NULL,
    DepartmentIdsJson NVARCHAR(MAX) NULL,
    ResolvedCount     INT           NOT NULL CONSTRAINT DF_Bcast_Count DEFAULT (0),
    SuppressedCount   INT           NOT NULL CONSTRAINT DF_Bcast_Supp DEFAULT (0),
    ResolvedUtc       DATETIME2(3)  NOT NULL CONSTRAINT DF_Bcast_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Broadcast_Document FOREIGN KEY (DocumentId) REFERENCES docaya.Document(DocumentId),
    CONSTRAINT FK_Broadcast_Version  FOREIGN KEY (VersionId)  REFERENCES docaya.DocumentVersion(VersionId),
    CONSTRAINT CK_Broadcast_Json CHECK (DepartmentIdsJson IS NULL OR ISJSON(DepartmentIdsJson) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Ntf_Broadcast')
    ALTER TABLE ntf.Notification ADD CONSTRAINT FK_Ntf_Broadcast
        FOREIGN KEY (BroadcastId) REFERENCES ntf.BroadcastAudience(BroadcastId);
GO

/*--------------------------------------------------------- ntf.ReadingList */
IF OBJECT_ID('ntf.ReadingList') IS NULL
CREATE TABLE ntf.ReadingList (
    ReadingListId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReadingList PRIMARY KEY,
    PrincipalId     UNIQUEIDENTIFIER NOT NULL,
    DocumentId      UNIQUEIDENTIFIER NOT NULL,
    AssignedUtc     DATETIME2(3) NOT NULL CONSTRAINT DF_Read_Assigned DEFAULT (SYSUTCDATETIME()),
    AcknowledgedUtc DATETIME2(3) NULL,
    DueUtc          DATE         NULL,
    CONSTRAINT UQ_ReadingList UNIQUE (PrincipalId, DocumentId),
    CONSTRAINT FK_Reading_Principal FOREIGN KEY (PrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Reading_Document  FOREIGN KEY (DocumentId)  REFERENCES docaya.Document(DocumentId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ReadingList_Outstanding' AND object_id = OBJECT_ID(N'ntf.ReadingList'))
CREATE NONCLUSTERED INDEX IX_ReadingList_Outstanding ON ntf.ReadingList (PrincipalId, DueUtc) WHERE AcknowledgedUtc IS NULL;
GO

/*----------------------------------------------------- ntf.DeliveryAttempt */
IF OBJECT_ID('ntf.DeliveryAttempt') IS NULL
CREATE TABLE ntf.DeliveryAttempt (
    AttemptId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DeliveryAttempt PRIMARY KEY,
    NotificationId BIGINT        NOT NULL,
    AttemptNo      INT           NOT NULL CONSTRAINT DF_Attempt_No DEFAULT (1),
    ChannelCode    NVARCHAR(16)  NOT NULL,
    Outcome        NVARCHAR(16)  NOT NULL,
    ProviderRef    NVARCHAR(200) NULL,
    ErrorText      NVARCHAR(MAX) NULL,
    AttemptedUtc   DATETIME2(3)  NOT NULL CONSTRAINT DF_Attempt_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Attempt_Notification FOREIGN KEY (NotificationId)
        REFERENCES ntf.Notification(NotificationId) ON DELETE CASCADE,
    CONSTRAINT CK_Attempt_Outcome CHECK (Outcome IN
        (N'Sent', N'Failed', N'Suppressed', N'Deferred'))
);
GO

PRINT '08 · ntf notification schema ready.';
GO
