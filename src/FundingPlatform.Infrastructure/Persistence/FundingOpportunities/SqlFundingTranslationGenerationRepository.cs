using System.Data;
using System.Text.Json;
using Dapper;
using FundingPlatform.Application.FundingOpportunities;
using FundingPlatform.Infrastructure.Persistence.Sql;
using Microsoft.Data.SqlClient;

namespace FundingPlatform.Infrastructure.Persistence.FundingOpportunities;

public sealed class SqlFundingTranslationGenerationRepository(ISqlConnectionFactory connections) : IFundingTranslationGenerationRepository
{
    public async Task<FundingTranslationGenerationReservation> ReserveAsync(Guid actor, Guid opportunity, string language,
        int sourceContentVersion, byte[] sourceRowVersion, FundingTranslationGenerationOptions options, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            var result = await connection.QuerySingleAsync<string>(new CommandDefinition(
                "dbo.FundingPlatform_usp_FundingTranslationGeneration_Reserve", new
                {
                    UserPublicId = actor, OpportunityPublicId = opportunity, Language = language,
                    SourceContentVersion = sourceContentVersion, SourceRowVersion = sourceRowVersion,
                    options.Model, options.MaximumCostUsdPerRequest, options.MonthlyBudgetUsd, options.MonthlyRequestLimit
                }, commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
            return JsonSerializer.Deserialize<FundingTranslationGenerationReservation>(result, FundingTranslationGenerationService.Json)!;
        }
        catch (SqlException error) { throw new FundingTranslationDataException(error.Number, error); }
    }
    public Task CompleteAsync(Guid actor, Guid generationId, FundingTranslationGeneratedText result, CancellationToken token) =>
        FinishAsync(actor, generationId, JsonSerializer.Serialize(result.Text, FundingTranslationGenerationService.Json), result.InputTokens, result.OutputTokens, token);
    public Task FailAsync(Guid actor, Guid generationId, CancellationToken token) => FinishAsync(actor, generationId, null, null, null, token);

    private async Task FinishAsync(Guid actor, Guid generationId, string? text, int? inputTokens, int? outputTokens, CancellationToken token)
    {
        await using var connection = connections.CreateConnection();
        try
        {
            await connection.ExecuteAsync(new CommandDefinition("dbo.FundingPlatform_usp_FundingTranslationGeneration_Finish", new
            {
                UserPublicId = actor, GenerationId = generationId, TextJson = text, InputTokens = inputTokens, OutputTokens = outputTokens
            }, commandType: CommandType.StoredProcedure, commandTimeout: 15, cancellationToken: token));
        }
        catch (SqlException error) { throw new FundingTranslationDataException(error.Number, error); }
    }
}
