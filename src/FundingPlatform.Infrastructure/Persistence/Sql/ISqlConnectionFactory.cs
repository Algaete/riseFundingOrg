using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.Sql;

public interface ISqlConnectionFactory
{
    SqlConnection CreateConnection();
}
