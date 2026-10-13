using System.Data;
using System.Data.Common;
using System.Globalization;
using System.Security.Claims;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

using Docaya.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;

namespace Docaya.Api.Endpoints;

/// <summary>
/// Contract-named business endpoints.
/// </summary>
public static partial class ContractEndpoints
{
    private const string NotImplementedCode = "docaya.operation_not_implemented";
    private const string AnonymousPrincipalId = "docaya-prototype";
    private const string AnonymousPrincipalName = "Docaya Prototype User";

    /// <summary>
    /// Maps the v1 business surface from the OpenAPI contract.
    /// </summary>
    /// <param name="app">The endpoint route builder.</param>
    /// <returns>The same builder, for chaining.</returns>
    public static IEndpointRouteBuilder MapContractEndpoints(this IEndpointRouteBuilder app)
    {
        ArgumentNullException.ThrowIfNull(app);

        var group = app.MapGroup("/api/v1").RequireAuthorization();

        group.MapPost("/documents", CreateDocumentAsync)
            .AllowAnonymous()
            .WithName("createDocument")
            .WithTags("Documents");
        group.MapGet("/documents", ListDocumentsAsync)
            .AllowAnonymous()
            .WithName("listDocuments")
            .WithTags("Documents");
        group.MapGet("/documents/{id:guid}", GetDocumentAsync)
            .AllowAnonymous()
            .WithName("getDocument")
            .WithTags("Documents");
        group.MapPost("/documents/{id:guid}/chunks", NotReady)
            .WithName("uploadDocumentChunk")
            .WithTags("Documents");
        group.MapPatch("/documents/{id:guid}/registration", UpdateDocumentAsync)
            .AllowAnonymous()
            .WithName("updateDocumentRegistration")
            .WithTags("Documents");
        group.MapPut("/documents/{id:guid}/classification", NotReady)
            .WithName("setDocumentClassification")
            .WithTags("Documents");
        group.MapPost("/documents/{id:guid}/submit", NotReady)
            .WithName("submitDocument")
            .WithTags("Documents");
        group.MapGet("/documents/{id:guid}/timeline", NotReady)
            .WithName("getDocumentTimeline")
            .WithTags("Documents");
        group.MapGet("/documents/{id:guid}/versions/{version:int}/thumbnail", NotReady)
            .WithName("getDocumentVersionThumbnail")
            .WithTags("Documents");
        group.MapPost("/documents/{id:guid}/revisions", NotReady)
            .WithName("createDocumentRevision")
            .WithTags("Revisions");
        group.MapPost("/reviews/{taskId:guid}/decisions", NotReady)
            .WithName("recordReviewDecision")
            .WithTags("Reviews");
        group.MapPost("/reviews/{taskId:guid}/sla-extension", NotReady)
            .WithName("grantSlaExtension")
            .WithTags("Reviews");
        group.MapGet("/search", NotReady)
            .WithName("search")
            .WithTags("Discovery");
        group.MapPost("/ask", NotReady)
            .WithName("ask")
            .WithTags("Discovery");
        group.MapGet("/analytics/embed-configuration", NotReady)
            .WithName("getAnalyticsEmbedConfiguration")
            .WithTags("Analytics");
        group.MapGet("/admin/review-routes", NotReady)
            .WithName("listReviewRoutes")
            .WithTags("Administration");

        return app;
    }

    private static async Task<IResult> CreateDocumentAsync(
        DocumentRegistrationRequest request,
        DocayaDbContext db,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        var connection = db.Database.GetDbConnection();
        await EnsureOpenAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var departmentId = await EnsureDepartmentAsync(connection, transaction, request.Department, cancellationToken);
        var principalId = await EnsurePrincipalAsync(connection, transaction, context.User, departmentId, cancellationToken);
        var classId = await EnsureDocumentClassAsync(connection, transaction, request.Kind ?? request.Type, cancellationToken);
        var sensitivityId = await FindRequiredIdAsync(
            connection,
            transaction,
            "SELECT TOP (1) SensitivityId FROM ref.Sensitivity WHERE SensitivityCode = @value OR DisplayNameEn = @value ORDER BY SensitivityId",
            NormalizeSensitivity(request.Sensitivity ?? request.Classification),
            cancellationToken);
        var scopeId = await FindRequiredIdAsync(
            connection,
            transaction,
            "SELECT TOP (1) ScopeId FROM ref.PublishingScope WHERE ScopeCode = @value OR DisplayNameEn = @value ORDER BY ScopeId",
            NormalizeScope(request.Scope),
            cancellationToken);
        var priorityId = await FindRequiredIdAsync(
            connection,
            transaction,
            "SELECT TOP (1) PriorityId FROM ref.Priority WHERE PriorityCode = @value OR DisplayNameEn = @value ORDER BY PriorityId",
            NormalizePriority(request.Priority),
            cancellationToken);
        var trackingNumber = await ResolveTrackingNumberAsync(
            connection,
            transaction,
            request.Id ?? request.Number,
            cancellationToken);
        var documentId = Guid.NewGuid();
        var statusCode = NormalizeStatus(request.Status);
        var createdUtc = DateTimeOffset.UtcNow;
        var expiry = ParseDate(request.Expiry ?? request.NextReview);

        await ExecuteAsync(
            connection,
            transaction,
            """
            INSERT INTO docaya.Document
                (DocumentId, TrackingNumber, StatusCode, ClassId, SensitivityId, DepartmentId,
                 PublishingScopeId, PriorityId, BusinessTitle, BusinessTitleAr, Description,
                 ExternalReference, OwnerPrincipalId, ExpiryUtc, DetectedLanguage, CreatedUtc, CreatedByPrincipalId)
            VALUES
                (@documentId, @trackingNumber, @statusCode, @classId, @sensitivityId, @departmentId,
                 @scopeId, @priorityId, @title, @titleAr, @summary,
                 @reference, @principalId, @expiry, @language, @createdUtc, @principalId)
            """,
            cancellationToken,
            Parameter("@documentId", documentId),
            Parameter("@trackingNumber", trackingNumber),
            Parameter("@statusCode", statusCode),
            Parameter("@classId", classId),
            Parameter("@sensitivityId", sensitivityId),
            Parameter("@departmentId", departmentId),
            Parameter("@scopeId", scopeId),
            Parameter("@priorityId", priorityId),
            Parameter("@title", RequiredText(request.Title, "title")),
            Parameter("@titleAr", EmptyToNull(request.TitleAr)),
            Parameter("@summary", EmptyToNull(request.Summary)),
            Parameter("@reference", EmptyToNull(request.Reference)),
            Parameter("@principalId", principalId),
            Parameter("@expiry", expiry?.ToDateTime(TimeOnly.MinValue)),
            Parameter("@language", request.Language ?? "en"),
            Parameter("@createdUtc", createdUtc.UtcDateTime));

        if (request.Size.GetValueOrDefault(request.SizeBytes.GetValueOrDefault()) > 0)
        {
            await SaveStagedFileAsync(connection, transaction, request, documentId, principalId, cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        var document = ToDocumentResponse(request, documentId, trackingNumber, statusCode, createdUtc, expiry);
        return Results.Ok(new { document, record = document });
    }

    private static async Task<IResult> ListDocumentsAsync(
        DocayaDbContext db,
        string? q,
        int? limit,
        CancellationToken cancellationToken)
    {
        var connection = db.Database.GetDbConnection();
        await EnsureOpenAsync(connection, cancellationToken);
        var rows = await ReadDocumentsAsync(connection, null, q, Math.Clamp(limit ?? 100, 1, 500), cancellationToken);
        return Results.Ok(new { documents = rows });
    }

    private static async Task<IResult> GetDocumentAsync(
        Guid id,
        DocayaDbContext db,
        CancellationToken cancellationToken)
    {
        var connection = db.Database.GetDbConnection();
        await EnsureOpenAsync(connection, cancellationToken);
        var rows = await ReadDocumentsAsync(connection, id, null, 1, cancellationToken);
        return rows.Count == 0 ? Results.NotFound() : Results.Ok(new { document = rows[0] });
    }

    private static async Task<IResult> UpdateDocumentAsync(
        Guid id,
        DocumentRegistrationRequest request,
        DocayaDbContext db,
        HttpContext context,
        CancellationToken cancellationToken)
    {
        var connection = db.Database.GetDbConnection();
        await EnsureOpenAsync(connection, cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        var departmentId = await EnsureDepartmentAsync(connection, transaction, request.Department, cancellationToken);
        var principalId = await EnsurePrincipalAsync(connection, transaction, context.User, departmentId, cancellationToken);
        var statusCode = NormalizeStatus(request.Status);
        await ExecuteAsync(
            connection,
            transaction,
            """
            UPDATE docaya.Document
            SET StatusCode = @statusCode,
                BusinessTitle = COALESCE(@title, BusinessTitle),
                Description = COALESCE(@summary, Description),
                ModifiedUtc = SYSUTCDATETIME(),
                ModifiedByPrincipalId = @principalId
            WHERE DocumentId = @documentId
            """,
            cancellationToken,
            Parameter("@statusCode", statusCode),
            Parameter("@title", EmptyToNull(request.Title)),
            Parameter("@summary", EmptyToNull(request.Summary)),
            Parameter("@principalId", principalId),
            Parameter("@documentId", id));

        await transaction.CommitAsync(cancellationToken);
        var rows = await ReadDocumentsAsync(connection, id, null, 1, cancellationToken);
        return rows.Count == 0 ? Results.NotFound() : Results.Ok(new { document = rows[0] });
    }

    private static async Task SaveStagedFileAsync(
        DbConnection connection,
        DbTransaction transaction,
        DocumentRegistrationRequest request,
        Guid documentId,
        Guid principalId,
        CancellationToken cancellationToken)
    {
        var sessionId = Guid.NewGuid();
        var fileName = RequiredText(request.FileName ?? request.SourcePath, "fileName");
        var size = Math.Max(1, request.Size.GetValueOrDefault(request.SizeBytes.GetValueOrDefault(1)));
        var mime = string.IsNullOrWhiteSpace(request.Mime) ? request.MimeType : request.Mime;
        var sha256 = ParseSha256(request.Hash);
        var blobContainer = "docaya-staging";
        var blobUri = $"docaya://metadata-only/{documentId:N}/{Uri.EscapeDataString(fileName)}";

        await ExecuteAsync(
            connection,
            transaction,
            """
            INSERT INTO stg.UploadSession
                (SessionId, DocumentId, OriginalFileName, DeclaredMimeType, TotalBytes,
                 ReceivedBytes, StateCode, CreatedUtc, ExpiresUtc, CommittedUtc, CreatedBy)
            VALUES
                (@sessionId, @documentId, @fileName, @mime, @size,
                 @size, N'Committed', SYSUTCDATETIME(), DATEADD(day, 7, SYSUTCDATETIME()), SYSUTCDATETIME(), @principalId)
            """,
            cancellationToken,
            Parameter("@sessionId", sessionId),
            Parameter("@documentId", documentId),
            Parameter("@fileName", fileName),
            Parameter("@mime", EmptyToNull(mime)),
            Parameter("@size", size),
            Parameter("@principalId", principalId));

        await ExecuteAsync(
            connection,
            transaction,
            """
            INSERT INTO stg.StagedFile
                (StagedFileId, DocumentId, SessionId, BlobUri, BlobContainer, SizeBytes,
                 MimeDetected, FileExtension, Sha256, CommittedUtc)
            VALUES
                (@stagedFileId, @documentId, @sessionId, @blobUri, @blobContainer, @size,
                 @mime, @extension, @sha256, SYSUTCDATETIME())
            """,
            cancellationToken,
            Parameter("@stagedFileId", Guid.NewGuid()),
            Parameter("@documentId", documentId),
            Parameter("@sessionId", sessionId),
            Parameter("@blobUri", blobUri),
            Parameter("@blobContainer", blobContainer),
            Parameter("@size", size),
            Parameter("@mime", string.IsNullOrWhiteSpace(mime) ? "application/octet-stream" : mime),
            Parameter("@extension", Path.GetExtension(fileName).TrimStart('.')),
            Parameter("@sha256", sha256));
    }

    private static async Task<List<DocumentResponse>> ReadDocumentsAsync(
        DbConnection connection,
        Guid? documentId,
        string? query,
        int limit,
        CancellationToken cancellationToken)
    {
        const string Sql = """
            SELECT TOP (@limit)
                d.DocumentId, d.TrackingNumber, d.StatusCode, d.BusinessTitle, d.BusinessTitleAr,
                d.Description, d.ExternalReference, d.ExpiryUtc, d.DetectedLanguage, d.CreatedUtc, d.ModifiedUtc,
                c.DisplayNameEn AS ClassName, dep.DisplayNameEn AS DepartmentName, s.DisplayNameEn AS SensitivityName,
                ps.DisplayNameEn AS ScopeName, p.DisplayNameEn AS PriorityName,
                pr.DisplayName AS OwnerName,
                sf.BlobUri, sf.SizeBytes, sf.MimeDetected, sf.FileExtension,
                CONVERT(VARCHAR(64), sf.Sha256, 2) AS HashHex
            FROM docaya.Document d
            JOIN ref.DocumentClass c ON c.ClassId = d.ClassId
            JOIN ref.Department dep ON dep.DepartmentId = d.DepartmentId
            JOIN ref.Sensitivity s ON s.SensitivityId = d.SensitivityId
            JOIN ref.PublishingScope ps ON ps.ScopeId = d.PublishingScopeId
            JOIN ref.Priority p ON p.PriorityId = d.PriorityId
            JOIN sec.Principal pr ON pr.PrincipalId = d.OwnerPrincipalId
            OUTER APPLY (
                SELECT TOP (1) *
                FROM stg.StagedFile sf
                WHERE sf.DocumentId = d.DocumentId
                ORDER BY sf.CommittedUtc DESC
            ) sf
            WHERE (@documentId IS NULL OR d.DocumentId = @documentId)
              AND (@query IS NULL OR d.TrackingNumber LIKE @queryLike OR d.BusinessTitle LIKE @queryLike)
            ORDER BY d.CreatedUtc DESC
            """;

        await using var command = CreateCommand(
            connection,
            null,
            Sql,
            Parameter("@limit", limit),
            Parameter("@documentId", documentId),
            Parameter("@query", EmptyToNull(query)),
            Parameter("@queryLike", string.IsNullOrWhiteSpace(query) ? null : $"%{query.Trim()}%"));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        var rows = new List<DocumentResponse>();
        while (await reader.ReadAsync(cancellationToken))
        {
            rows.Add(FromReader(reader));
        }

        return rows;
    }

    private static DocumentResponse FromReader(DbDataReader reader)
    {
        var trackingNumber = ReadRequiredString(reader, "TrackingNumber");
        var status = ReadRequiredString(reader, "StatusCode");
        var updatedAt = ReadDateTime(reader, "ModifiedUtc") ?? ReadDateTime(reader, "CreatedUtc") ?? DateTime.UtcNow;
        var title = ReadRequiredString(reader, "BusinessTitle");
        var className = ReadRequiredString(reader, "ClassName");
        var department = ReadRequiredString(reader, "DepartmentName");
        var sensitivity = ReadRequiredString(reader, "SensitivityName");
        var summary = ReadString(reader, "Description") ?? string.Empty;
        var size = ReadInt64(reader, "SizeBytes") ?? 0;
        var mime = ReadString(reader, "MimeDetected") ?? string.Empty;
        var fileExtension = ReadString(reader, "FileExtension");
        var fileName = string.IsNullOrWhiteSpace(fileExtension) ? title : $"{title}.{fileExtension}";

        return new DocumentResponse(
            Id: trackingNumber,
            DocumentId: reader.GetGuid("DocumentId"),
            Number: trackingNumber,
            Title: title,
            TitleAr: ReadString(reader, "BusinessTitleAr") ?? string.Empty,
            Kind: className,
            Type: className,
            Library: className,
            Department: department,
            Sensitivity: sensitivity,
            Classification: sensitivity == "Secret" ? "Restricted" : sensitivity,
            Status: status,
            Owner: ReadRequiredString(reader, "OwnerName"),
            Summary: summary,
            SummaryAr: string.Empty,
            Reference: ReadString(reader, "ExternalReference") ?? string.Empty,
            FileName: fileName,
            Mime: mime,
            Size: size,
            Hash: ReadString(reader, "HashHex")?.ToLowerInvariant() ?? string.Empty,
            Captured: (ReadDateTime(reader, "CreatedUtc") ?? DateTime.UtcNow).ToString("O", CultureInfo.InvariantCulture),
            Expiry: ReadDate(reader, "ExpiryUtc") ?? string.Empty,
            Flow: "Single",
            Priority: ReadRequiredString(reader, "PriorityName"),
            Scope: ReadRequiredString(reader, "ScopeName"),
            Approvals: Array.Empty<string>(),
            Version: status == "Published" ? 1 : 0,
            Revision: status == "Published" ? 1 : 0,
            Indexed: false,
            Hold: string.Empty,
            Declared: false,
            Location: ReadString(reader, "BlobUri") ?? "SQL metadata",
            Staging: size > 0 ? "Committed" : "MetadataOnly",
            Note: string.Empty,
            Due: status == "PendingApproval" ? DateTime.UtcNow.AddHours(48).ToString("O", CultureInfo.InvariantCulture) : string.Empty,
            Delegated: false,
            Signature: string.Empty,
            Language: ReadString(reader, "DetectedLanguage") ?? "en",
            SourcePath: ReadString(reader, "BlobUri") ?? string.Empty,
            Retention: "7 years",
            NextReview: ReadDate(reader, "ExpiryUtc") ?? string.Empty,
            UpdatedAt: updatedAt.ToString("O", CultureInfo.InvariantCulture),
            WorkflowStep: status == "PendingApproval" ? 2 : 1,
            Reviewer: string.Empty,
            Approver: string.Empty,
            SharePointFolderId: null,
            SharePointFolderName: null,
            SharePointFolderPath: null);
    }

    private static DocumentResponse ToDocumentResponse(
        DocumentRegistrationRequest request,
        Guid documentId,
        string trackingNumber,
        string statusCode,
        DateTimeOffset createdUtc,
        DateOnly? expiry)
    {
        var kind = request.Kind ?? request.Type ?? "Document";
        var sensitivity = NormalizeSensitivity(request.Sensitivity ?? request.Classification);
        var size = request.Size.GetValueOrDefault(request.SizeBytes.GetValueOrDefault());
        return new DocumentResponse(
            Id: trackingNumber,
            DocumentId: documentId,
            Number: trackingNumber,
            Title: RequiredText(request.Title, "title"),
            TitleAr: request.TitleAr ?? string.Empty,
            Kind: kind,
            Type: kind,
            Library: request.Library ?? kind,
            Department: RequiredText(request.Department, "department"),
            Sensitivity: sensitivity,
            Classification: sensitivity == "Secret" ? "Restricted" : sensitivity,
            Status: statusCode,
            Owner: request.Owner ?? AnonymousPrincipalName,
            Summary: request.Summary ?? string.Empty,
            SummaryAr: request.SummaryAr ?? string.Empty,
            Reference: request.Reference ?? string.Empty,
            FileName: request.FileName ?? request.SourcePath ?? string.Empty,
            Mime: request.Mime ?? request.MimeType ?? string.Empty,
            Size: size,
            Hash: request.Hash ?? string.Empty,
            Captured: createdUtc.ToString("O", CultureInfo.InvariantCulture),
            Expiry: expiry?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? string.Empty,
            Flow: request.Flow ?? "Single",
            Priority: NormalizePriority(request.Priority),
            Scope: request.Scope ?? "Departmental",
            Approvals: request.Approvals ?? Array.Empty<string>(),
            Version: statusCode == "Published" ? Math.Max(1, request.Version.GetValueOrDefault()) : 0,
            Revision: statusCode == "Published" ? Math.Max(1, request.Revision.GetValueOrDefault()) : 0,
            Indexed: request.Indexed.GetValueOrDefault(),
            Hold: request.Hold ?? string.Empty,
            Declared: request.Declared.GetValueOrDefault(),
            Location: size > 0 ? "SQL staging metadata" : "SQL metadata",
            Staging: size > 0 ? "Committed" : "MetadataOnly",
            Note: request.Note ?? string.Empty,
            Due: request.Due ?? string.Empty,
            Delegated: request.Delegated.GetValueOrDefault(),
            Signature: request.Signature ?? string.Empty,
            Language: request.Language ?? "en",
            SourcePath: request.SourcePath ?? string.Empty,
            Retention: request.Retention ?? "7 years",
            NextReview: request.NextReview ?? expiry?.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) ?? string.Empty,
            UpdatedAt: createdUtc.ToString("O", CultureInfo.InvariantCulture),
            WorkflowStep: statusCode == "PendingApproval" ? 2 : 1,
            Reviewer: request.Reviewer ?? string.Empty,
            Approver: request.Approver ?? string.Empty,
            SharePointFolderId: request.SharePointFolderId,
            SharePointFolderName: request.SharePointFolderName,
            SharePointFolderPath: request.SharePointFolderPath);
    }

    private static async Task<int> EnsureDocumentClassAsync(
        DbConnection connection,
        DbTransaction transaction,
        string? value,
        CancellationToken cancellationToken)
    {
        var name = string.IsNullOrWhiteSpace(value) ? "Correspondence" : value.Trim();
        var code = NormalizeDocumentClassCode(name);
        return await FindRequiredIdAsync(
            connection,
            transaction,
            "SELECT TOP (1) ClassId FROM ref.DocumentClass WHERE DisplayNameEn = @value OR ClassCode = @value OR ClassCode = @code ORDER BY ClassId",
            cancellationToken,
            Parameter("@value", name),
            Parameter("@code", code));
    }

    private static async Task<int> EnsureDepartmentAsync(
        DbConnection connection,
        DbTransaction transaction,
        string? value,
        CancellationToken cancellationToken)
    {
        var name = string.IsNullOrWhiteSpace(value) ? "Operations" : value.Trim();
        var code = NormalizeDepartmentCode(name);
        return await FindRequiredIdAsync(
            connection,
            transaction,
            "SELECT TOP (1) DepartmentId FROM ref.Department WHERE DisplayNameEn = @value OR DepartmentCode = @value OR DepartmentCode = @code ORDER BY DepartmentId",
            cancellationToken,
            Parameter("@value", name),
            Parameter("@code", code));
    }

    private static async Task<Guid> EnsurePrincipalAsync(
        DbConnection connection,
        DbTransaction transaction,
        ClaimsPrincipal user,
        int departmentId,
        CancellationToken cancellationToken)
    {
        var externalId = user.FindFirstValue("oid")
            ?? user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? AnonymousPrincipalId;
        var truncatedExternalId = externalId[..Math.Min(externalId.Length, 64)];
        var id = await ScalarAsync<Guid>(
            connection,
            transaction,
            "SELECT PrincipalId FROM sec.Principal WHERE ExternalObjectId = @externalId",
            cancellationToken,
            Parameter("@externalId", truncatedExternalId));

        if (id.HasValue)
        {
            return id.Value;
        }

        if (truncatedExternalId != AnonymousPrincipalId)
        {
            var anonymousId = await ScalarAsync<Guid>(
                connection,
                transaction,
                "SELECT PrincipalId FROM sec.Principal WHERE ExternalObjectId = @externalId",
                cancellationToken,
                Parameter("@externalId", AnonymousPrincipalId));
            if (anonymousId.HasValue)
            {
                return anonymousId.Value;
            }
        }

        throw new InvalidOperationException("The Docaya prototype SQL principal has not been seeded.");
    }

    private static async Task<string> ResolveTrackingNumberAsync(
        DbConnection connection,
        DbTransaction transaction,
        string? requested,
        CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(requested) && TrackingNumberRegex().IsMatch(requested))
        {
            var existing = await ScalarAsync<int>(
                connection,
                transaction,
                "SELECT COUNT(1) FROM docaya.Document WHERE TrackingNumber = @trackingNumber",
                cancellationToken,
                Parameter("@trackingNumber", requested));
            if (existing.GetValueOrDefault() == 0)
            {
                return requested;
            }
        }

        var year = DateTime.UtcNow.Year;
        var suffix = await ScalarAsync<int>(
            connection,
            transaction,
            """
            SELECT ISNULL(MAX(TRY_CONVERT(INT, RIGHT(TrackingNumber, 6))), 0)
            FROM docaya.Document WITH (UPDLOCK, HOLDLOCK)
            WHERE TrackingNumber LIKE @prefix
            """,
            cancellationToken,
            Parameter("@prefix", $"DOC-{year}-%"));
        return $"DOC-{year}-{suffix.GetValueOrDefault() + 1:000000}";
    }

    private static async Task<int> FindRequiredIdAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        string value,
        CancellationToken cancellationToken)
    {
        var id = await FindIdAsync(connection, transaction, sql, value, cancellationToken);
        return id ?? throw new InvalidOperationException($"Reference value '{value}' was not found.");
    }

    private static async Task<int> FindRequiredIdAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken cancellationToken,
        params DbParameterValue[] parameters)
    {
        var id = await ScalarAsync<int>(connection, transaction, sql, cancellationToken, parameters);
        return id ?? throw new InvalidOperationException("Required reference value was not found.");
    }

    private static async Task<int?> FindIdAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        string value,
        CancellationToken cancellationToken)
    {
        return await ScalarAsync<int>(
            connection,
            transaction,
            sql,
            cancellationToken,
            Parameter("@value", value));
    }

    private static async Task<T?> ScalarAsync<T>(
        DbConnection connection,
        DbTransaction? transaction,
        string sql,
        CancellationToken cancellationToken,
        params DbParameterValue[] parameters)
        where T : struct
    {
        await using var command = CreateCommand(connection, transaction, sql, parameters);
        var value = await command.ExecuteScalarAsync(cancellationToken);
        if (value is null || value == DBNull.Value)
        {
            return null;
        }

        return value is T typed
            ? typed
            : (T)Convert.ChangeType(value, typeof(T), CultureInfo.InvariantCulture);
    }

    private static async Task ExecuteAsync(
        DbConnection connection,
        DbTransaction transaction,
        string sql,
        CancellationToken cancellationToken,
        params DbParameterValue[] parameters)
    {
        await using var command = CreateCommand(connection, transaction, sql, parameters);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static DbCommand CreateCommand(
        DbConnection connection,
        DbTransaction? transaction,
        string sql,
        params DbParameterValue[] parameters)
    {
        var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = sql;
        foreach (var parameterValue in parameters)
        {
            var parameter = command.CreateParameter();
            parameter.ParameterName = parameterValue.Name;
            parameter.Value = parameterValue.Value ?? DBNull.Value;
            command.Parameters.Add(parameter);
        }

        return command;
    }

    private static async Task EnsureOpenAsync(DbConnection connection, CancellationToken cancellationToken)
    {
        if (connection.State != ConnectionState.Open)
        {
            await connection.OpenAsync(cancellationToken);
        }
    }

    private static DbParameterValue Parameter(string name, object? value) => new(name, value);

    private static string NormalizeStatus(string? status)
    {
        return status switch
        {
            "Under Review" or "Under Approval" => "PendingApproval",
            "Pending approval" => "PendingApproval",
            "MetadataOnly" => "Draft",
            null or "" => "Draft",
            _ => status.Replace(" ", string.Empty, StringComparison.Ordinal),
        };
    }

    private static string NormalizeSensitivity(string? value)
    {
        return value switch
        {
            "Restricted" or "Secret" => "Secret",
            "Confidential" => "Confidential",
            "Public" => "Public",
            _ => "Internal",
        };
    }

    private static string NormalizeScope(string? value)
    {
        return value switch
        {
            "Organisation-wide" or "Organization-wide" or "OrgWide" => "OrgWide",
            "Public" => "Public",
            "Clearance level" or "Clearance" or "Cross-departmental" => "CrossDepartmental",
            _ => "Departmental",
        };
    }

    private static string NormalizePriority(string? value)
    {
        return value switch
        {
            "Urgent" => "Urgent",
            "Priority" or "High" => "Priority",
            _ => "Routine",
        };
    }

    private static string NormalizeDepartmentCode(string value)
    {
        return value switch
        {
            "Human Resources" => "HR",
            "Information Technology" => "IT",
            "Operations" => "OPS",
            "Legal" => "LEG",
            "Health and Safety" => "HSE",
            _ => "OPS",
        };
    }

    private static string NormalizeDocumentClassCode(string value)
    {
        return value switch
        {
            "Memo" or "Circular" or "Memo / Circular" => "MEMO",
            "HR Record" => "HRRECORD",
            "Work Instruction" or "Manual" or "Form" => "PROCEDURE",
            "Standard" => "STDEVIDENCE",
            "Correspondence" => "CORRESPONDENCE",
            "Contract" => "CONTRACT",
            "Report" => "REPORT",
            "Policy" => "POLICY",
            "Procedure" => "PROCEDURE",
            _ => "CORRESPONDENCE",
        };
    }

    private static string RequiredText(string? value, string name)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"'{name}' is required.");
        }

        return value.Trim();
    }

    private static string? EmptyToNull(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static DateOnly? ParseDate(string? value)
    {
        if (DateOnly.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
        {
            return date;
        }

        return null;
    }

    private static byte[] ParseSha256(string? value)
    {
        if (!string.IsNullOrWhiteSpace(value) && value.Length == 64)
        {
            try
            {
                return Convert.FromHexString(value);
            }
            catch (FormatException)
            {
            }
        }

        return Convert.FromHexString("0000000000000000000000000000000000000000000000000000000000000000");
    }

    private static string ToCode(string value, int maxLength)
    {
        var text = CodeRegex().Replace(value.ToUpperInvariant(), string.Empty);
        return (string.IsNullOrWhiteSpace(text) ? "DOC" : text)[..Math.Min(maxLength, Math.Max(1, text.Length))];
    }

    private static string ReadRequiredString(DbDataReader reader, string name) => ReadString(reader, name) ?? string.Empty;

    private static string? ReadString(DbDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }

    private static long? ReadInt64(DbDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt64(ordinal);
    }

    private static DateTime? ReadDateTime(DbDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        return reader.IsDBNull(ordinal) ? null : reader.GetDateTime(ordinal);
    }

    private static string? ReadDate(DbDataReader reader, string name)
    {
        var ordinal = reader.GetOrdinal(name);
        if (reader.IsDBNull(ordinal))
        {
            return null;
        }

        var value = reader.GetValue(ordinal);
        return value switch
        {
            DateTime dateTime => dateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            DateOnly dateOnly => dateOnly.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            _ => Convert.ToString(value, CultureInfo.InvariantCulture),
        };
    }

    private static IResult NotReady(HttpContext context)
    {
        var operation = context.GetEndpoint()?.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName
            ?? "unknownOperation";

        return Results.Problem(
            title: "Operation is not implemented.",
            detail: $"{operation} is present in the contract and requires its application use case before release.",
            statusCode: StatusCodes.Status501NotImplemented,
            extensions: new Dictionary<string, object?>
            {
                ["code"] = NotImplementedCode,
                ["correlationId"] = context.TraceIdentifier,
            });
    }

    [GeneratedRegex("^DOC-[0-9]{4}-[0-9]{6}$")]
    private static partial Regex TrackingNumberRegex();

    [GeneratedRegex("[^A-Z0-9]")]
    private static partial Regex CodeRegex();

    private sealed record DbParameterValue(string Name, object? Value);

    private sealed record DocumentRegistrationRequest(
        string? Id,
        string? Number,
        string? Title,
        string? TitleAr,
        string? Kind,
        string? Type,
        string? Library,
        string? Department,
        string? Sensitivity,
        string? Classification,
        string? Status,
        string? Owner,
        string? Summary,
        string? SummaryAr,
        string? Reference,
        string? FileName,
        string? Mime,
        long? Size,
        string? Hash,
        string? Captured,
        string? Expiry,
        string? Flow,
        string? Priority,
        string? Scope,
        string[]? Approvals,
        int? Version,
        bool? Indexed,
        string? Hold,
        bool? Declared,
        string? Location,
        string? Staging,
        string? Note,
        string? Due,
        bool? Delegated,
        string? Signature,
        string? Language,
        string? SourcePath,
        string? Retention,
        string? NextReview,
        int? Revision,
        int? WorkflowStep,
        string? Reviewer,
        string? Approver,
        string? SharePointFolderId,
        string? SharePointFolderName,
        string? SharePointFolderPath,
        string? MimeType,
        long? SizeBytes);

    private sealed record DocumentResponse(
        string Id,
        Guid DocumentId,
        string Number,
        string Title,
        string TitleAr,
        string Kind,
        string Type,
        string Library,
        string Department,
        string Sensitivity,
        string Classification,
        string Status,
        string Owner,
        string Summary,
        string SummaryAr,
        string Reference,
        string FileName,
        string Mime,
        long Size,
        string Hash,
        string Captured,
        string Expiry,
        string Flow,
        string Priority,
        string Scope,
        string[] Approvals,
        int Version,
        int Revision,
        bool Indexed,
        string Hold,
        bool Declared,
        string Location,
        string Staging,
        string Note,
        string Due,
        bool Delegated,
        string Signature,
        string Language,
        string SourcePath,
        string Retention,
        string NextReview,
        string UpdatedAt,
        int WorkflowStep,
        string Reviewer,
        string Approver,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SharePointFolderId,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SharePointFolderName,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SharePointFolderPath);
}
