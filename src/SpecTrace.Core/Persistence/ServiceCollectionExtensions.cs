using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace SpecTrace.Core.Persistence;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers AppDbContext with the Npgsql provider (dev/test default).
    /// For SQL Server / Azure SQL, call UseNpgsql's counterpart from the host project
    /// instead of calling this method.
    /// </summary>
    public static IServiceCollection AddSpecTracePersistencePostgres(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException(
                "ConnectionStrings:DefaultConnection is required. " +
                "Add it to appsettings.json or as an environment variable.");

        services.AddDbContext<AppDbContext>(opts =>
            opts.UseNpgsql(connectionString, npgsql =>
                npgsql.MigrationsAssembly(typeof(AppDbContext).Assembly.FullName)));

        return services;
    }
}
