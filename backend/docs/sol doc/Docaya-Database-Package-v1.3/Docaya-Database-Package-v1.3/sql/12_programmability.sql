/*==============================================================================
  12 · PROGRAMMABILITY  ·  FUNCTIONS AND STORED PROCEDURES
  Working-day arithmetic, tracking-number issuance, the audit hash chain,
  route resolution and the SLA sweep.                       TAD 8.3 / 11.6.1
==============================================================================*/
SET NOCOUNT ON; SET XACT_ABORT ON;
GO

/*-------------------------------------------- docaya.TrackingSequence (table) */
IF OBJECT_ID('docaya.TrackingSequence') IS NULL
CREATE TABLE docaya.TrackingSequence (
    SequenceYear INT NOT NULL CONSTRAINT PK_TrackingSequence PRIMARY KEY,
    LastValue    INT NOT NULL CONSTRAINT DF_TrackSeq_Last DEFAULT (0),
    CONSTRAINT CK_TrackSeq_Value CHECK (LastValue >= 0 AND LastValue <= 999999)
);
GO

/*------------------------------------------------------- ref.fn_IsWorkingDay
  DATEFIRST-independent: 1900-01-01 was a Monday, so
  ((DATEDIFF(DAY,0,@Date)+1) % 7) + 1 yields 1 = Sunday .. 7 = Saturday
  regardless of the session DATEFIRST setting.                               */
CREATE OR ALTER FUNCTION ref.fn_IsWorkingDay
(
    @CalendarCode NVARCHAR(24),
    @VersionNo    INT,
    @Date         DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @dow TINYINT = ((DATEDIFF(DAY, 0, @Date) + 1) % 7) + 1;
    IF EXISTS (SELECT 1 FROM ref.WorkingWeek
               WHERE CalendarCode = @CalendarCode AND VersionNo = @VersionNo
                 AND DayOfWeekNo = @dow AND IsWorkingDay = 0)
        RETURN 0;
    IF EXISTS (SELECT 1 FROM ref.HolidayCalendar
               WHERE CalendarCode = @CalendarCode AND VersionNo = @VersionNo
                 AND HolidayDate = @Date)
        RETURN 0;
    RETURN 1;
END;
GO

/*----------------------------------------------------- ref.fn_AddWorkingDays
  Sets OriginalTargetUtc at submission (Urgent = 12, Normal = 30).           */
CREATE OR ALTER FUNCTION ref.fn_AddWorkingDays
(
    @CalendarCode NVARCHAR(24),
    @VersionNo    INT,
    @StartDate    DATE,
    @WorkingDays  INT
)
RETURNS DATE
AS
BEGIN
    DECLARE @d DATE = @StartDate, @added INT = 0, @guard INT = 0;
    WHILE @added < @WorkingDays AND @guard < 4000
    BEGIN
        SET @d = DATEADD(DAY, 1, @d);
        SET @guard += 1;
        IF ref.fn_IsWorkingDay(@CalendarCode, @VersionNo, @d) = 1
            SET @added += 1;
    END
    RETURN @d;
END;
GO

/*------------------------------------------------ ref.fn_WorkingDaysBetween
  The remaining-working-days counter shown on every in-flight request.       */
CREATE OR ALTER FUNCTION ref.fn_WorkingDaysBetween
(
    @CalendarCode NVARCHAR(24),
    @VersionNo    INT,
    @FromDate     DATE,
    @ToDate       DATE
)
RETURNS INT
AS
BEGIN
    IF @FromDate IS NULL OR @ToDate IS NULL RETURN NULL;
    DECLARE @sign INT = CASE WHEN @ToDate < @FromDate THEN -1 ELSE 1 END;
    DECLARE @a DATE = CASE WHEN @sign = 1 THEN @FromDate ELSE @ToDate END;
    DECLARE @b DATE = CASE WHEN @sign = 1 THEN @ToDate   ELSE @FromDate END;
    DECLARE @count INT = 0, @d DATE = @a, @guard INT = 0;
    WHILE @d < @b AND @guard < 4000
    BEGIN
        SET @d = DATEADD(DAY, 1, @d);
        SET @guard += 1;
        IF ref.fn_IsWorkingDay(@CalendarCode, @VersionNo, @d) = 1
            SET @count += 1;
    END
    RETURN @count * @sign;
END;
GO

/*------------------------------------------ docaya.usp_IssueTrackingNumber
  Atomic issuance of DOC-YYYY-NNNNNN.                                        */
CREATE OR ALTER PROCEDURE docaya.usp_IssueTrackingNumber
    @TrackingNumber NVARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @year INT = DATEPART(YEAR, SYSUTCDATETIME());
    DECLARE @next INT;
    DECLARE @issued TABLE (LastValue INT);

    MERGE docaya.TrackingSequence WITH (HOLDLOCK) AS t
    USING (SELECT @year AS SequenceYear) AS s
        ON t.SequenceYear = s.SequenceYear
    WHEN MATCHED THEN UPDATE SET LastValue = t.LastValue + 1
    WHEN NOT MATCHED THEN INSERT (SequenceYear, LastValue) VALUES (@year, 1)
    OUTPUT inserted.LastValue INTO @issued(LastValue);

    SELECT @next = LastValue FROM @issued;

    IF @next IS NULL OR @next > 999999
        THROW 51003, N'Tracking number sequence exhausted for the current year.', 1;

    SET @TrackingNumber = CONCAT(N'DOC-', @year, N'-', FORMAT(@next, N'000000'));
END;
GO

/*----------------------------------------------- aud.usp_AppendAuditEvent
  Appends ONE row and computes Hash = SHA2_256( PrevHash || canonical payload ).
  Serialised with an application lock so the chain cannot fork.              */
CREATE OR ALTER PROCEDURE aud.usp_AppendAuditEvent
    @DocumentId       UNIQUEIDENTIFIER = NULL,
    @VersionId        UNIQUEIDENTIFIER = NULL,
    @ActorPrincipalId UNIQUEIDENTIFIER,
    @ExecutorIdentity NVARCHAR(128),
    @ActionCode       NVARCHAR(48),
    @ObjectType       NVARCHAR(48)  = NULL,
    @ObjectRef        NVARCHAR(200) = NULL,
    @Outcome          NVARCHAR(16)  = N'Success',
    @RequestId        NVARCHAR(64),
    @SourceIp         NVARCHAR(45)  = NULL,
    @UserAgent        NVARCHAR(400) = NULL,
    @PolicyVersionId  INT           = NULL,
    @PayloadJson      NVARCHAR(MAX) = NULL,
    @AuditEventId     BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @ownTran BIT = 0;
    IF @@TRANCOUNT = 0 BEGIN BEGIN TRANSACTION; SET @ownTran = 1; END

    EXEC sp_getapplock @Resource = N'aud.AuditEvent.chain',
                       @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 15000;

    DECLARE @prev BINARY(32) =
        ISNULL((SELECT TOP (1) Hash FROM aud.AuditEvent WITH (UPDLOCK)
                ORDER BY AuditEventId DESC), CONVERT(BINARY(32), REPLICATE(CHAR(0), 32)));

    DECLARE @occurred DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @canonical NVARCHAR(MAX) = CONCAT(
        CONVERT(NVARCHAR(36), @DocumentId), N'|', CONVERT(NVARCHAR(36), @VersionId), N'|',
        CONVERT(NVARCHAR(36), @ActorPrincipalId), N'|', @ExecutorIdentity, N'|',
        @ActionCode, N'|', ISNULL(@ObjectType, N''), N'|', ISNULL(@ObjectRef, N''), N'|',
        @Outcome, N'|', @RequestId, N'|', ISNULL(@SourceIp, N''), N'|',
        CONVERT(NVARCHAR(33), @occurred, 126), N'|', ISNULL(@PayloadJson, N''));

    DECLARE @hash BINARY(32) =
        HASHBYTES('SHA2_256', CONVERT(VARBINARY(MAX), @prev) + CONVERT(VARBINARY(MAX), @canonical));

    INSERT INTO aud.AuditEvent
        (DocumentId, VersionId, ActorPrincipalId, ExecutorIdentity, ActionCode,
         ObjectType, ObjectRef, Outcome, RequestId, SourceIp, UserAgent,
         PolicyVersionId, PayloadJson, PrevHash, Hash, OccurredUtc)
    VALUES
        (@DocumentId, @VersionId, @ActorPrincipalId, @ExecutorIdentity, @ActionCode,
         @ObjectType, @ObjectRef, @Outcome, @RequestId, @SourceIp, @UserAgent,
         @PolicyVersionId, @PayloadJson, @prev, @hash, @occurred);

    SET @AuditEventId = SCOPE_IDENTITY();

    IF @ownTran = 1 COMMIT TRANSACTION;
END;
GO

/*------------------------------------------------------ aud.usp_VerifyChain
  Recomputes the chain from the last verified checkpoint.                    */
CREATE OR ALTER PROCEDURE aud.usp_VerifyChain
    @FromAuditEventId BIGINT = NULL,
    @CreateCheckpoint BIT    = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @start BIGINT = ISNULL(@FromAuditEventId,
        ISNULL((SELECT MAX(UpToAuditEventId) FROM aud.ChainCheckpoint WHERE VerificationOk = 1), 0));

    DECLARE @expectedPrev BINARY(32) =
        ISNULL((SELECT Hash FROM aud.AuditEvent WHERE AuditEventId = @start),
               CONVERT(BINARY(32), REPLICATE(CHAR(0), 32)));

    DECLARE @broken TABLE (AuditEventId BIGINT, Problem NVARCHAR(128));
    DECLARE @id BIGINT, @prev BINARY(32), @hash BINARY(32), @recomputed BINARY(32);
    DECLARE @doc UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @actor UNIQUEIDENTIFIER;
    DECLARE @exec NVARCHAR(128), @act NVARCHAR(48), @otype NVARCHAR(48), @oref NVARCHAR(200);
    DECLARE @out NVARCHAR(16), @req NVARCHAR(64), @ip NVARCHAR(45);
    DECLARE @occ DATETIME2(3), @pay NVARCHAR(MAX);
    DECLARE @count BIGINT = 0;
    DECLARE @canon NVARCHAR(MAX);

    DECLARE c CURSOR LOCAL FAST_FORWARD FOR
        SELECT AuditEventId, PrevHash, Hash, DocumentId, VersionId, ActorPrincipalId,
               ExecutorIdentity, ActionCode, ObjectType, ObjectRef, Outcome,
               RequestId, SourceIp, OccurredUtc, PayloadJson
        FROM aud.AuditEvent WHERE AuditEventId > @start ORDER BY AuditEventId;
    OPEN c;
    FETCH NEXT FROM c INTO @id, @prev, @hash, @doc, @ver, @actor, @exec, @act,
                            @otype, @oref, @out, @req, @ip, @occ, @pay;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @count += 1;
        IF @prev <> @expectedPrev
            INSERT INTO @broken VALUES (@id, N'PrevHash does not match preceding row');

        SET @canon = CONCAT(
            CONVERT(NVARCHAR(36), @doc), N'|', CONVERT(NVARCHAR(36), @ver), N'|',
            CONVERT(NVARCHAR(36), @actor), N'|', @exec, N'|', @act, N'|',
            ISNULL(@otype, N''), N'|', ISNULL(@oref, N''), N'|', @out, N'|', @req, N'|',
            ISNULL(@ip, N''), N'|', CONVERT(NVARCHAR(33), @occ, 126), N'|', ISNULL(@pay, N''));

        SET @recomputed = HASHBYTES('SHA2_256',
            CONVERT(VARBINARY(MAX), @prev) + CONVERT(VARBINARY(MAX), @canon));

        IF @recomputed <> @hash
            INSERT INTO @broken VALUES (@id, N'Row hash does not match its content');

        SET @expectedPrev = @hash;
        FETCH NEXT FROM c INTO @id, @prev, @hash, @doc, @ver, @actor, @exec, @act,
                                @otype, @oref, @out, @req, @ip, @occ, @pay;
    END
    CLOSE c; DEALLOCATE c;

    DECLARE @ok BIT = CASE WHEN EXISTS (SELECT 1 FROM @broken) THEN 0 ELSE 1 END;
    DECLARE @last BIGINT = ISNULL((SELECT MAX(AuditEventId) FROM aud.AuditEvent), @start);

    IF @CreateCheckpoint = 1 AND @ok = 1 AND @last > @start
        INSERT INTO aud.ChainCheckpoint (UpToAuditEventId, ChainHash, EventCount, VerifiedUtc, VerificationOk)
        VALUES (@last, @expectedPrev, @count, SYSUTCDATETIME(), 1);

    SELECT VerificationOk = @ok, EventsChecked = @count, UpToAuditEventId = @last;
    SELECT * FROM @broken ORDER BY AuditEventId;
END;
GO

/*-------------------------------------------------------- wf.usp_ResolveRoute
  Most specific wins: Department > Class > Global.                           */
CREATE OR ALTER PROCEDURE wf.usp_ResolveRoute
    @DocumentClassId   INT,
    @DepartmentId      INT,
    @RouteDefinitionId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) @RouteDefinitionId = RouteDefinitionId
    FROM wf.RouteDefinition
    WHERE IsActive = 1
      AND (EffectiveToUtc IS NULL OR EffectiveToUtc > SYSUTCDATETIME())
      AND EffectiveFromUtc <= SYSUTCDATETIME()
      AND (
            (ScopeType = N'Department' AND DepartmentId = @DepartmentId)
         OR (ScopeType = N'Class'      AND DocumentClassId = @DocumentClassId)
         OR (ScopeType = N'Global')
          )
    ORDER BY CASE ScopeType WHEN N'Department' THEN 1 WHEN N'Class' THEN 2 ELSE 3 END,
             VersionNo DESC;

    IF @RouteDefinitionId IS NULL
        THROW 51001, N'No active review route resolves for this class and department.', 1;
END;
GO

/*---------------------------------------------------- wf.usp_SweepSlaStatus
  Timer job. Raises AtRisk and Overdue exactly once each.                    */
CREATE OR ALTER PROCEDURE wf.usp_SweepSlaStatus
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @jobRunId BIGINT;

    INSERT INTO ops.JobRun (JobName) VALUES (N'wf.usp_SweepSlaStatus');
    SET @jobRunId = SCOPE_IDENTITY();

    DECLARE @open TABLE (
        WorkflowInstanceId UNIQUEIDENTIFIER, CalendarCode NVARCHAR(24),
        CalendarVersionNo INT, CurrentTargetUtc DATE, RequestType NVARCHAR(16),
        IsAtRisk BIT, IsOverdue BIT, Remaining INT NULL, WarnWindow INT NULL);

    INSERT INTO @open (WorkflowInstanceId, CalendarCode, CalendarVersionNo,
                       CurrentTargetUtc, RequestType, IsAtRisk, IsOverdue)
    SELECT wi.WorkflowInstanceId, wi.CalendarCode, wi.CalendarVersionNo,
           wi.CurrentTargetUtc, wi.RequestType, wi.IsAtRisk, wi.IsOverdue
    FROM wf.WorkflowInstance wi
    WHERE wi.CompletedUtc IS NULL AND wi.StateCode IN (N'Running', N'Returned');

    UPDATE o
       SET Remaining  = ref.fn_WorkingDaysBetween(o.CalendarCode, o.CalendarVersionNo,
                                                  @today, o.CurrentTargetUtc),
           WarnWindow = ISNULL((SELECT TOP (1) AtRiskWindowDays FROM ref.SlaTarget
                                WHERE RequestType = o.RequestType AND IsActive = 1
                                ORDER BY CASE ScopeType WHEN N'Department' THEN 1
                                                        WHEN N'Class' THEN 2 ELSE 3 END), 3)
      FROM @open o;

    INSERT INTO wf.SlaEvent (WorkflowInstanceId, EventType, PreviousTargetUtc,
                             NewTargetUtc, RemainingDays, ReasonText)
    SELECT o.WorkflowInstanceId, N'Overdue', o.CurrentTargetUtc, o.CurrentTargetUtc,
           o.Remaining, N'Current target date has passed.'
    FROM @open o WHERE o.Remaining < 0 AND o.IsOverdue = 0;

    INSERT INTO wf.SlaEvent (WorkflowInstanceId, EventType, PreviousTargetUtc,
                             NewTargetUtc, RemainingDays, ReasonText)
    SELECT o.WorkflowInstanceId, N'AtRisk', o.CurrentTargetUtc, o.CurrentTargetUtc,
           o.Remaining, N'Remaining working days fall inside the configured warning window.'
    FROM @open o
    WHERE o.Remaining >= 0 AND o.Remaining <= o.WarnWindow AND o.IsAtRisk = 0 AND o.IsOverdue = 0;

    UPDATE wi
       SET IsOverdue = CASE WHEN o.Remaining < 0 THEN 1 ELSE 0 END,
           IsAtRisk  = CASE WHEN o.Remaining >= 0 AND o.Remaining <= o.WarnWindow THEN 1 ELSE 0 END
      FROM wf.WorkflowInstance wi
      JOIN @open o ON o.WorkflowInstanceId = wi.WorkflowInstanceId;

    DECLARE @changed INT = @@ROWCOUNT;
    DECLARE @read    INT = (SELECT COUNT(*) FROM @open);

    UPDATE ops.JobRun
       SET CompletedUtc = SYSUTCDATETIME(), Outcome = N'Success',
           ItemsRead = @read, ItemsChanged = @changed
     WHERE JobRunId = @jobRunId;
END;
GO

/*---------------------------------------------------- ops.usp_EnqueueOutbox
  Call INSIDE the same transaction as the state change.                      */
CREATE OR ALTER PROCEDURE ops.usp_EnqueueOutbox
    @AggregateType NVARCHAR(48),
    @AggregateId   UNIQUEIDENTIFIER,
    @EventType     NVARCHAR(64),
    @PayloadJson   NVARCHAR(MAX),
    @CorrelationId NVARCHAR(64),
    @SessionKey    NVARCHAR(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF ISJSON(@PayloadJson) = 0
        THROW 51002, N'Outbox payload must be valid JSON.', 1;
    INSERT INTO ops.OutboxMessage
        (AggregateType, AggregateId, EventType, PayloadJson, CorrelationId, SessionKey)
    VALUES
        (@AggregateType, @AggregateId, @EventType, @PayloadJson, @CorrelationId,
         ISNULL(@SessionKey, CONVERT(NVARCHAR(36), @AggregateId)));
END;
GO

/*------------------------------------------- docaya.usp_PurgeStagingArtifacts
  M5 staging lifecycle. Never touches the registry or audit.                 */
CREATE OR ALTER PROCEDURE docaya.usp_PurgeStagingArtifacts
    @RetainHours INT = 24
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    DECLARE @jobRunId BIGINT;
    INSERT INTO ops.JobRun (JobName) VALUES (N'docaya.usp_PurgeStagingArtifacts');
    SET @jobRunId = SCOPE_IDENTITY();

    DELETE fc
      FROM stg.FileChunk fc
      JOIN stg.UploadSession us ON us.SessionId = fc.SessionId
     WHERE us.StateCode = N'Committed'
       AND us.CommittedUtc < DATEADD(HOUR, -@RetainHours, SYSUTCDATETIME());
    DECLARE @chunks INT = @@ROWCOUNT;

    UPDATE stg.UploadSession
       SET StateCode = N'Expired'
     WHERE StateCode = N'Open' AND ExpiresUtc < SYSUTCDATETIME();

    UPDATE sf
       SET ReconciledUtc   = SYSUTCDATETIME(),
           ReconcileAction = N'Purged'
      FROM stg.StagedFile sf
      JOIN docaya.Document d ON d.DocumentId = sf.DocumentId
     WHERE sf.ReconciledUtc IS NULL
       AND d.StatusCode = N'Published'
       AND EXISTS (SELECT 1 FROM ops.PromotionLedger pl
                    WHERE pl.DocumentId = sf.DocumentId AND pl.ResultCode = N'Succeeded');
    DECLARE @reconciled INT = @@ROWCOUNT;

    UPDATE ops.JobRun
       SET CompletedUtc = SYSUTCDATETIME(), Outcome = N'Success',
           ItemsChanged = @chunks + @reconciled
     WHERE JobRunId = @jobRunId;
END;
GO

PRINT '12 · programmability ready.';
GO
