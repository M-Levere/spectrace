using Microsoft.EntityFrameworkCore;

namespace SpecTrace.Core.Persistence;

/// <summary>
/// EF Core context. Provider-agnostic: configure the provider via the options builder,
/// not here. Dev/test uses Npgsql (PostgreSQL); company deploy swaps to SQL Server /
/// Azure SQL by changing the provider and connection string in config — no code changes.
/// </summary>
public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Entity configurations are registered here as they are introduced per phase.
        // Phase 7 will add the full schema.
    }
}
