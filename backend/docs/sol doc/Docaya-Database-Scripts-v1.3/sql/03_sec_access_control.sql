/*==============================================================================
  03 · sec  ·  ACCESS CONTROL  (RBAC + ABAC, policy, decision log)
  Security-sensitive and separated so policy changes are independently
  auditable and the decision log can be retained differently.  TAD 11.7 / 14.
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*----------------------------------------------------------------- sec.Role */
IF OBJECT_ID('sec.Role') IS NULL
CREATE TABLE sec.Role (
    RoleCode            NVARCHAR(48) NOT NULL CONSTRAINT PK_sec_Role PRIMARY KEY,
    DisplayNameEn       NVARCHAR(96) NOT NULL,
    DisplayNameAr       NVARCHAR(96) NULL,
    Description         NVARCHAR(400) NULL,
    IsWorkflowStageRole BIT NOT NULL CONSTRAINT DF_Role_Stage  DEFAULT (0),
    CanApprove          BIT NOT NULL CONSTRAINT DF_Role_Appr   DEFAULT (0),
    CanExtendSla        BIT NOT NULL CONSTRAINT DF_Role_Ext    DEFAULT (0),
    CanManageRetention  BIT NOT NULL CONSTRAINT DF_Role_Ret    DEFAULT (0),
    CanViewAudit        BIT NOT NULL CONSTRAINT DF_Role_Audit  DEFAULT (0),
    CanConfigure        BIT NOT NULL CONSTRAINT DF_Role_Cfg    DEFAULT (0),
    RequiresStepUpAuth  BIT NOT NULL CONSTRAINT DF_Role_Step   DEFAULT (0),
    IsActive            BIT NOT NULL CONSTRAINT DF_Role_Active DEFAULT (1)
);
GO

/*------------------------------------------------------------ sec.Principal */
IF OBJECT_ID('sec.Principal') IS NULL
CREATE TABLE sec.Principal (
    PrincipalId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_sec_Principal PRIMARY KEY
                          CONSTRAINT DF_Principal_Id DEFAULT (NEWID()),
    ExternalObjectId  NVARCHAR(64)  NOT NULL,
    PrincipalType     NVARCHAR(16)  NOT NULL,
    UserPrincipalName NVARCHAR(256) NULL,
    DisplayName       NVARCHAR(200) NOT NULL,
    DisplayNameAr     NVARCHAR(200) NULL,
    Email             NVARCHAR(256) NULL,
    DepartmentId      INT           NULL,
    EmploymentStatus  NVARCHAR(24)  NOT NULL CONSTRAINT DF_Principal_Emp DEFAULT (N'Active'),
    PreferredLanguage NVARCHAR(8)   NOT NULL CONSTRAINT DF_Principal_Lang DEFAULT (N'en'),
    IsActive          BIT           NOT NULL CONSTRAINT DF_Principal_Active DEFAULT (1),
    FirstSignInUtc    DATETIME2(3)  NULL,
    LastSeenUtc       DATETIME2(3)  NULL,
    CreatedUtc        DATETIME2(3)  NOT NULL CONSTRAINT DF_Principal_Created DEFAULT (SYSUTCDATETIME()),
    RowVersion        ROWVERSION    NOT NULL,
    CONSTRAINT UQ_sec_Principal_External UNIQUE (ExternalObjectId),
    CONSTRAINT FK_Principal_Department FOREIGN KEY (DepartmentId)
        REFERENCES ref.Department(DepartmentId),
    CONSTRAINT CK_sec_Principal_Type CHECK (PrincipalType IN (N'User', N'Group', N'Workload')),
    CONSTRAINT CK_sec_Principal_Emp  CHECK (EmploymentStatus IN (N'Active', N'Suspended', N'Left'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Principal_Dept_Active' AND object_id = OBJECT_ID(N'sec.Principal'))
CREATE NONCLUSTERED INDEX IX_Principal_Dept_Active ON sec.Principal (DepartmentId, IsActive) INCLUDE (DisplayName, Email);
GO

/*------------------------------------------------------- sec.RoleAssignment (RBAC) */
IF OBJECT_ID('sec.RoleAssignment') IS NULL
CREATE TABLE sec.RoleAssignment (
    AssignmentId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_RoleAssignment PRIMARY KEY,
    PrincipalId    UNIQUEIDENTIFIER NOT NULL,
    RoleCode       NVARCHAR(48) NOT NULL,
    ScopeType      NVARCHAR(24) NOT NULL CONSTRAINT DF_RA_ScopeType DEFAULT (N'Global'),
    ScopeId        INT          NULL,
    GrantedUtc     DATETIME2(3) NOT NULL CONSTRAINT DF_RA_Granted DEFAULT (SYSUTCDATETIME()),
    GrantedBy      UNIQUEIDENTIFIER NULL,
    ExpiresUtc     DATETIME2(3) NULL,
    Justification  NVARCHAR(400) NULL,
    IsActive       BIT          NOT NULL CONSTRAINT DF_RA_Active DEFAULT (1),
    CONSTRAINT FK_RoleAssignment_Principal FOREIGN KEY (PrincipalId)
        REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_RoleAssignment_Role FOREIGN KEY (RoleCode) REFERENCES sec.Role(RoleCode),
    CONSTRAINT FK_RoleAssignment_GrantedBy FOREIGN KEY (GrantedBy)
        REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_sec_RA_Scope CHECK (ScopeType IN (N'Global', N'Department', N'Class'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_RoleAssignment_Principal' AND object_id = OBJECT_ID(N'sec.RoleAssignment'))
CREATE NONCLUSTERED INDEX IX_RoleAssignment_Principal ON sec.RoleAssignment (PrincipalId, IsActive) INCLUDE (RoleCode, ScopeType, ScopeId, ExpiresUtc);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_RoleAssignment_Expiry' AND object_id = OBJECT_ID(N'sec.RoleAssignment'))
CREATE NONCLUSTERED INDEX IX_RoleAssignment_Expiry ON sec.RoleAssignment (ExpiresUtc) WHERE ExpiresUtc IS NOT NULL AND IsActive = 1;
GO

/*--------------------------------------------------------- sec.AbacAttribute
  Clearance and scope live HERE, not in the token, so revocation is immediate. */
IF OBJECT_ID('sec.AbacAttribute') IS NULL
CREATE TABLE sec.AbacAttribute (
    AttributeId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_AbacAttribute PRIMARY KEY,
    PrincipalId      UNIQUEIDENTIFIER NOT NULL,
    AttributeKey     NVARCHAR(48)  NOT NULL,
    AttributeValue   NVARCHAR(128) NOT NULL,
    EffectiveFromUtc DATETIME2(3)  NOT NULL CONSTRAINT DF_Abac_From DEFAULT (SYSUTCDATETIME()),
    EffectiveToUtc   DATETIME2(3)  NULL,
    GrantedBy        UNIQUEIDENTIFIER NULL,
    CONSTRAINT FK_Abac_Principal FOREIGN KEY (PrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT FK_Abac_GrantedBy FOREIGN KEY (GrantedBy)   REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Abac_Principal_Key' AND object_id = OBJECT_ID(N'sec.AbacAttribute'))
CREATE NONCLUSTERED INDEX IX_Abac_Principal_Key ON sec.AbacAttribute (PrincipalId, AttributeKey)
    INCLUDE (AttributeValue, EffectiveFromUtc, EffectiveToUtc);
GO

/*----------------------------------------------------------- sec.PolicyVersion */
IF OBJECT_ID('sec.PolicyVersion') IS NULL
CREATE TABLE sec.PolicyVersion (
    PolicyVersionId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_PolicyVersion PRIMARY KEY,
    VersionNo       INT           NOT NULL,
    PublishedUtc    DATETIME2(3)  NOT NULL CONSTRAINT DF_PolVer_Pub DEFAULT (SYSUTCDATETIME()),
    PublishedBy     UNIQUEIDENTIFIER NULL,
    IsCurrent       BIT           NOT NULL CONSTRAINT DF_PolVer_Cur DEFAULT (0),
    Notes           NVARCHAR(400) NULL,
    CONSTRAINT UQ_sec_PolicyVersion UNIQUE (VersionNo),
    CONSTRAINT FK_PolicyVersion_By FOREIGN KEY (PublishedBy) REFERENCES sec.Principal(PrincipalId)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PolicyVersion_Current' AND object_id = OBJECT_ID(N'sec.PolicyVersion'))
CREATE UNIQUE NONCLUSTERED INDEX UX_PolicyVersion_Current ON sec.PolicyVersion (IsCurrent) WHERE IsCurrent = 1;
GO

/*------------------------------------------------------------ sec.AccessPolicy */
IF OBJECT_ID('sec.AccessPolicy') IS NULL
CREATE TABLE sec.AccessPolicy (
    PolicyId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_AccessPolicy PRIMARY KEY,
    PolicyVersionId INT           NOT NULL,
    PolicyCode      NVARCHAR(64)  NOT NULL,
    EffectCode      NVARCHAR(8)   NOT NULL,
    SubjectExpr     NVARCHAR(MAX) NOT NULL,
    ResourceExpr    NVARCHAR(MAX) NOT NULL,
    ActionCode      NVARCHAR(32)  NOT NULL,
    Priority        INT           NOT NULL CONSTRAINT DF_Policy_Prio DEFAULT (100),
    Description     NVARCHAR(400) NULL,
    IsActive        BIT           NOT NULL CONSTRAINT DF_Policy_Active DEFAULT (1),
    CONSTRAINT UQ_sec_AccessPolicy UNIQUE (PolicyVersionId, PolicyCode),
    CONSTRAINT FK_AccessPolicy_Version FOREIGN KEY (PolicyVersionId)
        REFERENCES sec.PolicyVersion(PolicyVersionId),
    CONSTRAINT CK_sec_Policy_Effect CHECK (EffectCode IN (N'Permit', N'Deny')),
    CONSTRAINT CK_sec_Policy_Json   CHECK (ISJSON(SubjectExpr) = 1 AND ISJSON(ResourceExpr) = 1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_AccessPolicy_Version_Active' AND object_id = OBJECT_ID(N'sec.AccessPolicy'))
CREATE NONCLUSTERED INDEX IX_AccessPolicy_Version_Active ON sec.AccessPolicy (PolicyVersionId, IsActive, Priority) INCLUDE (EffectCode, ActionCode);
GO

/*-------------------------------------------------------- sec.AccessDecisionLog */
IF OBJECT_ID('sec.AccessDecisionLog') IS NULL
CREATE TABLE sec.AccessDecisionLog (
    DecisionId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_sec_AccessDecisionLog PRIMARY KEY,
    PrincipalId     UNIQUEIDENTIFIER NOT NULL,
    DocumentId      UNIQUEIDENTIFIER NULL,
    ActionCode      NVARCHAR(32)  NOT NULL,
    PolicyVersionId INT           NULL,
    MatchedPolicyId INT           NULL,
    Decision        NVARCHAR(8)   NOT NULL,
    ReasonCode      NVARCHAR(64)  NULL,
    SecurityKeys    NVARCHAR(MAX) NULL,
    CorrelationId   NVARCHAR(64)  NOT NULL,
    SourceIp        NVARCHAR(45)  NULL,
    DecidedUtc      DATETIME2(3)  NOT NULL CONSTRAINT DF_Decision_Utc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FK_Decision_Principal FOREIGN KEY (PrincipalId) REFERENCES sec.Principal(PrincipalId),
    CONSTRAINT CK_sec_Decision CHECK (Decision IN (N'Permit', N'Deny'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Decision_Principal_Time' AND object_id = OBJECT_ID(N'sec.AccessDecisionLog'))
CREATE NONCLUSTERED INDEX IX_Decision_Principal_Time ON sec.AccessDecisionLog (PrincipalId, DecidedUtc DESC) INCLUDE (ActionCode, Decision);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Decision_Document_Time' AND object_id = OBJECT_ID(N'sec.AccessDecisionLog'))
CREATE NONCLUSTERED INDEX IX_Decision_Document_Time ON sec.AccessDecisionLog (DocumentId, DecidedUtc DESC) WHERE DocumentId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Decision_Denials' AND object_id = OBJECT_ID(N'sec.AccessDecisionLog'))
CREATE NONCLUSTERED INDEX IX_Decision_Denials ON sec.AccessDecisionLog (DecidedUtc DESC, PrincipalId) WHERE Decision = N'Deny';
GO

PRINT '03 · sec schema ready.';
GO
