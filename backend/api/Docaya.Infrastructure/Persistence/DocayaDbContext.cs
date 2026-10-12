using Microsoft.EntityFrameworkCore;

namespace Docaya.Infrastructure.Persistence;

/// <summary>
/// The Docaya persistence context.
/// </summary>
/// <remarks>
/// <para>
/// Technical Architecture Document v1.3, Section 11. Entity configurations are applied
/// from this assembly and every entity is mapped into one of the schemas declared in
/// <see cref="DocayaSchemas"/>.
/// </para>
/// <para>
/// Access is by workload identity. No connection string containing a password appears
/// in configuration or code (TAD 14.6.3).
/// </para>
/// </remarks>
public class DocayaDbContext : DbContext
{
    /// <summary>Creates the context.</summary>
    /// <param name="options">Context options supplied by the host.</param>
    public DocayaDbContext(DbContextOptions<DocayaDbContext> options)
        : base(options)
    {
    }

    /// <inheritdoc />
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);

        // The registry schema is the default; every entity that belongs elsewhere
        // declares its schema explicitly in its configuration.
        modelBuilder.HasDefaultSchema(DocayaSchemas.Registry);

        modelBuilder.ApplyConfigurationsFromAssembly(typeof(DocayaDbContext).Assembly);

        base.OnModelCreating(modelBuilder);
    }
}
