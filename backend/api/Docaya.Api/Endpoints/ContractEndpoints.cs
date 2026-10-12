namespace Docaya.Api.Endpoints;

/// <summary>
/// Contract-named business endpoints that fail closed until their application use cases are bound.
/// </summary>
public static class ContractEndpoints
{
    private const string NotImplementedCode = "docaya.operation_not_implemented";

    /// <summary>
    /// Maps the authenticated v1 business surface from the OpenAPI contract.
    /// </summary>
    /// <param name="app">The endpoint route builder.</param>
    /// <returns>The same builder, for chaining.</returns>
    public static IEndpointRouteBuilder MapContractEndpoints(this IEndpointRouteBuilder app)
    {
        ArgumentNullException.ThrowIfNull(app);

        var group = app.MapGroup("/api/v1").RequireAuthorization();

        group.MapPost("/documents", NotReady)
            .WithName("createDocument")
            .WithTags("Documents");
        group.MapGet("/documents", NotReady)
            .WithName("listDocuments")
            .WithTags("Documents");
        group.MapGet("/documents/{id:guid}", NotReady)
            .WithName("getDocument")
            .WithTags("Documents");
        group.MapPost("/documents/{id:guid}/chunks", NotReady)
            .WithName("uploadDocumentChunk")
            .WithTags("Documents");
        group.MapPatch("/documents/{id:guid}/registration", NotReady)
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
}
