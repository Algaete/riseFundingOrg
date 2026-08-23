using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace FundingPlatform.Workers.Functions;

public sealed class HealthFunction
{
    [Function(nameof(HealthFunction))]
    public HttpResponseData Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequestData request)
    {
        var response = request.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json; charset=utf-8");
        response.WriteString("{\"status\":\"Healthy\",\"service\":\"FundingPlatform.Workers\"}");
        return response;
    }
}
