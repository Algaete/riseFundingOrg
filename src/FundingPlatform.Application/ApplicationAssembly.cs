using System.Reflection;

namespace FundingPlatform.Application;

public static class ApplicationAssembly
{
    public static Assembly Reference => typeof(ApplicationAssembly).Assembly;
}
