using System.Reflection;

namespace FundingPlatform.Infrastructure;

public static class InfrastructureAssembly
{
    public static Assembly Reference => typeof(InfrastructureAssembly).Assembly;
}
