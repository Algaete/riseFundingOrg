using System.Reflection;

namespace FundingPlatform.Core;

public static class CoreAssembly
{
    public static Assembly Reference => typeof(CoreAssembly).Assembly;
}
