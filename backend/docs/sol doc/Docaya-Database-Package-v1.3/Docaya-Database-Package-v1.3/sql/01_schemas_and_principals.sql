/*==============================================================================
  01 · SCHEMAS, DATABASE ROLES AND WORKLOAD PRINCIPALS
  Docaya v1.3 · TAD Section 11.2 and 14.6.3
==============================================================================*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*------------------------------------------------------------------ SCHEMAS */
IF SCHEMA_ID('stg')    IS NULL EXEC('CREATE SCHEMA stg    AUTHORIZATION dbo;');
IF SCHEMA_ID('docaya') IS NULL EXEC('CREATE SCHEMA docaya AUTHORIZATION dbo;');
IF SCHEMA_ID('wf')     IS NULL EXEC('CREATE SCHEMA wf     AUTHORIZATION dbo;');
IF SCHEMA_ID('sec')    IS NULL EXEC('CREATE SCHEMA sec    AUTHORIZATION dbo;');
IF SCHEMA_ID('ref')    IS NULL EXEC('CREATE SCHEMA ref    AUTHORIZATION dbo;');
IF SCHEMA_ID('idx')    IS NULL EXEC('CREATE SCHEMA idx    AUTHORIZATION dbo;');
IF SCHEMA_ID('ntf')    IS NULL EXEC('CREATE SCHEMA ntf    AUTHORIZATION dbo;');
IF SCHEMA_ID('aud')    IS NULL EXEC('CREATE SCHEMA aud    AUTHORIZATION dbo;');
IF SCHEMA_ID('ops')    IS NULL EXEC('CREATE SCHEMA ops    AUTHORIZATION dbo;');
IF SCHEMA_ID('rpt')    IS NULL EXEC('CREATE SCHEMA rpt    AUTHORIZATION dbo;');
GO

/*-------------------------------------------------------- APPLICATION ROLES */
/* One role per workload. Membership is granted to the managed-identity user. */
IF DATABASE_PRINCIPAL_ID('docaya_api_role')     IS NULL CREATE ROLE docaya_api_role;
IF DATABASE_PRINCIPAL_ID('docaya_capture_role') IS NULL CREATE ROLE docaya_capture_role;
IF DATABASE_PRINCIPAL_ID('docaya_worker_role')  IS NULL CREATE ROLE docaya_worker_role;
IF DATABASE_PRINCIPAL_ID('docaya_index_role')   IS NULL CREATE ROLE docaya_index_role;
IF DATABASE_PRINCIPAL_ID('docaya_report_role')  IS NULL CREATE ROLE docaya_report_role;
IF DATABASE_PRINCIPAL_ID('docaya_migrate_role') IS NULL CREATE ROLE docaya_migrate_role;
IF DATABASE_PRINCIPAL_ID('docaya_support_role') IS NULL CREATE ROLE docaya_support_role;
GO

/*----------------------------------------------------- WORKLOAD SQL USERS
  Azure SQL: users are created FROM EXTERNAL PROVIDER for managed identities.
  Names must match the managed-identity display names created by Bicep.
  NOTE: Requires an Entra-authenticated admin session.
------------------------------------------------------------------------*/
DECLARE @identities TABLE (UserName sysname, RoleName sysname);
INSERT INTO @identities (UserName, RoleName) VALUES
    (N'$(ApiIdentity)',       N'docaya_api_role'),
    (N'$(CaptureIdentity)',   N'docaya_capture_role'),
    (N'$(PromotionIdentity)', N'docaya_worker_role'),
    (N'$(WorkflowIdentity)',  N'docaya_worker_role'),
    (N'$(IndexingIdentity)',  N'docaya_index_role'),
    (N'$(AnalyticsIdentity)', N'docaya_report_role');

DECLARE @u sysname, @r sysname, @sql nvarchar(max);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT UserName, RoleName FROM @identities;
OPEN c; FETCH NEXT FROM c INTO @u, @r;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATABASE_PRINCIPAL_ID(@u) IS NULL
    BEGIN
        BEGIN TRY
            SET @sql = N'CREATE USER ' + QUOTENAME(@u) + N' FROM EXTERNAL PROVIDER;';
            EXEC sp_executesql @sql;
        END TRY
        BEGIN CATCH
            THROW;
        END CATCH
    END
    IF DATABASE_PRINCIPAL_ID(@u) IS NOT NULL
    BEGIN
        SET @sql = N'ALTER ROLE ' + QUOTENAME(@r) + N' ADD MEMBER ' + QUOTENAME(@u) + N';';
        EXEC sp_executesql @sql;
    END
    FETCH NEXT FROM c INTO @u, @r;
END
CLOSE c; DEALLOCATE c;
GO

PRINT '01 · schemas, roles and workload principals ready.';
GO
