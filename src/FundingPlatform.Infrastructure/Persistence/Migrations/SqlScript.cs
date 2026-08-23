namespace FundingPlatform.Infrastructure.Persistence.Migrations;

public sealed record SqlScript(
    int Sequence,
    string Name,
    string FileName,
    string Checksum,
    IReadOnlyList<string> Batches);
