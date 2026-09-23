using FundingPlatform.Application.Engagement;
using FundingPlatform.Application.Stories;
using FundingPlatform.Core.Engagement;
using FundingPlatform.Core.Stories;
using FundingPlatform.Core.Donations;
using FundingPlatform.Infrastructure.Notifications;
using FundingPlatform.Infrastructure.Persistence.Migrations;
using Microsoft.SqlServer.TransactSql.ScriptDom;
using System.Text.Json;

namespace FundingPlatform.UnitTests;

public sealed class EngagementTests
{
    [Theory]
    [InlineData("{\"items\":null,\"totalCount\":0,\"page\":1}")]
    [InlineData("{\"totalCount\":0,\"page\":1}")]
    [InlineData("{\"items\":[],\"totalCount\":0,\"page\":1}")]
    public void Empty_sql_json_pages_have_non_null_collections(string json)
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var stories = JsonSerializer.Deserialize<StoryPage>(json, options)!;
        var inquiries = JsonSerializer.Deserialize<InquiryPage>(json, options)!;
        Assert.Empty(stories.Items); Assert.Empty(inquiries.Items);
        Assert.Null(stories.Items.FirstOrDefault());
        Assert.Contains("\"items\":[]", JsonSerializer.Serialize(stories, options));
        Assert.Contains("\"items\":[]", JsonSerializer.Serialize(inquiries, options));
    }

    [Fact]
    public void Page_normalization_preserves_records_counts_and_page_number()
    {
        Story[] stories = [new(Guid.NewGuid(), Guid.NewGuid(), "Organización TEST", null, null,
            Story.Content!, 0, 1, DateTimeOffset.UtcNow)];
        Inquiry[] inquiries = [new(Guid.NewGuid(), Input, "Chile", 0, 0, 1, DateTimeOffset.UtcNow)];
        var storyPage = new StoryPage(stories, 21, 2);
        var inquiryPage = new InquiryPage(inquiries, 21, 2);
        Assert.Same(stories, storyPage.Items); Assert.Equal(21, storyPage.TotalCount); Assert.Equal(2, storyPage.Page);
        Assert.Same(inquiries, inquiryPage.Items); Assert.Equal(21, inquiryPage.TotalCount); Assert.Equal(2, inquiryPage.Page);
    }

    private static StoryWrite Story => new(0, new("Historia", null, "Un relato de trabajo en terreno.", "organization", null, [], [], []));
    private static InquiryInput Input => new(Guid.NewGuid(), "Ana", "ana@example.invalid", null, 152, "funding", null, null, null, null, "Necesitamos orientación para nuestro proyecto.", true);

    [Fact]
    public void Stories_are_optional_and_normalize_blank_and_duplicate_taxonomies()
    {
        var normalized = StoryRules.Normalize(Story with { Content = Story.Content! with { Title = " Historia ", Summary = " ", CategoryIds = [2, 1, 2], GoalIds = null, CountryIds = null } });
        Assert.Empty(StoryRules.Validate(normalized));
        Assert.Equal("Historia", normalized.Content!.Title); Assert.Null(normalized.Content.Summary);
        Assert.Equal([1, 2], normalized.Content.CategoryIds); Assert.Empty(normalized.Content.GoalIds!);
        Assert.Empty(normalized.Content.CountryIds!);
    }

    [Theory]
    [InlineData("title")][InlineData("body")][InlineData("kind")][InlineData("summary")]
    [InlineData("goals")][InlineData("countries")][InlineData("categories")][InlineData("project")][InlineData("revision")]
    public void Stories_reject_invalid_content(string field)
    {
        var c = Story.Content!;
        c = field switch { "title" => c with { Title = "x" }, "body" => c with { Body = "short" }, "kind" => c with { Kind = "other" },
            "summary" => c with { Summary = new string('x', 601) }, "goals" => c with { GoalIds = [18] }, "countries" => c with { CountryIds = [-1] },
            "categories" => c with { CategoryIds = Enumerable.Range(1, 31).ToArray() }, "project" => c with { ProjectId = Guid.Empty }, _ => c };
        Assert.NotEmpty(StoryRules.Validate(StoryRules.Normalize(new(field == "revision" ? -1 : 0, c))));
    }

    [Fact]
    public void Contact_normalizes_without_requiring_optional_organization_project_or_deadline()
    {
        var normalized = InquiryRules.Normalize(Input with { Name = " Ana ", Email = " ANA@example.invalid ", Organization = " ", Website = " " });
        Assert.Empty(InquiryRules.Validate(normalized)); Assert.Equal("Ana", normalized.Name);
        Assert.Equal("ana@example.invalid", normalized.Email); Assert.Null(normalized.Organization); Assert.Null(normalized.Website);
    }
    [Theory]
    [InlineData("consent")][InlineData("email")][InlineData("honeypot")][InlineData("country")][InlineData("description")]
    [InlineData("service")][InlineData("topic")][InlineData("service-topic")][InlineData("id")][InlineData("name")]
    public void Contact_rejects_invalid_inputs_before_storage(string field)
    {
        var d = Input;
        d = field switch { "consent" => d with { ConsentToContact = false }, "email" => d with { Email = "Ana <ana@example.invalid>" },
            "honeypot" => d with { Website = "robot" }, "country" => d with { CountryId = 0 }, "description" => d with { Description = "short" },
            "service" => d with { Topic = "service" }, "topic" => d with { Topic = "unknown" }, "service-topic" => d with { ServiceCode = "translation" },
            "id" => d with { RequestId = Guid.Empty }, _ => d with { Name = "Ana\r\nsecret" } };
        Assert.NotEmpty(InquiryRules.Validate(InquiryRules.Normalize(d)));
    }
    [Fact]
    public void Seven_quote_only_services_are_supported_without_a_price_or_provider()
    {
        Assert.Equal(7, ProfessionalServices.Codes.Distinct().Count());
        foreach (var code in ProfessionalServices.Codes) Assert.Empty(InquiryRules.Validate(Input with { Topic = "service", ServiceCode = code }));
        Assert.False(new DisabledInquiryTeamNotifier().Configured);
        Assert.False(new InquiryNotificationOptions().Enabled);
        var org = Guid.NewGuid();
        Assert.IsType<DonationRecipient.Organization>(new DonationRecipient.Organization(org));
        var project = new DonationRecipient.Project(org, Guid.NewGuid());
        Assert.Equal(org, project.OrganizationId);
    }
    [Theory]
    [InlineData(false, false)][InlineData(true, false)][InlineData(true, true)]
    public async Task Inquiry_is_durable_before_email_and_never_notified_twice(bool enabled, bool failure)
    {
        var repo = new Repository(); var notifier = new Notifier(repo.Events) { Configured = enabled, Fail = failure };
        var service = new InquiryService(repo, notifier); var d = Input;
        var first = await service.CaptureAsync(d, default); var replay = await service.CaptureAsync(d, default);
        Assert.False(first.WasReplay); Assert.True(replay.WasReplay); Assert.Equal(first.RequestId, replay.RequestId);
        Assert.Equal("capture", repo.Events.First()); Assert.Equal(enabled ? 1 : 0, notifier.Calls);
        Assert.Equal(enabled ? !failure : null, repo.Accepted);
        Assert.Equal(32, repo.Hash!.Length);
        if (enabled) Assert.Equal(["capture", "claim", "send", "finish", "capture", "claim"], repo.Events);
    }
    [Theory]
    [InlineData("Migrations", "061_organization_stories.sql")][InlineData("Migrations", "062_service_contact_inquiries.sql")]
    [InlineData("Tests", "061_organization_stories_smoke.sql")][InlineData("Tests", "062_service_contact_inquiries_smoke.sql")]
    public void New_sql_parses_without_executing_a_database(string folder, string name)
    {
        using var reader = new StringReader(Read(folder, name));
        new TSql170Parser(true).Parse(reader, out var errors);
        Assert.Empty(errors.Select(e => $"{e.Line}:{e.Column}: {e.Message}"));
    }
    [Fact]
    public void Sql_boundaries_preserve_tenancy_consent_privacy_and_notification_claiming()
    {
        var stories = Read("Migrations", "061_organization_stories.sql");
        foreach (var clause in new[] { "m.Role=1", "u.Status=2", "OrganizationId=@Org", "@Current<>@ExpectedRevision", "PersonalConsentConfirmed", "FundingPlatform_ifn_ProjectMarketplaceReady", "FundingPlatform_StoryHistory", "RightsConfirmed=0,PersonalConsentConfirmed=0" }) Assert.Contains(clause, stories);
        Assert.DoesNotContain("TO FundingPlatform_GeneralWorkerRole", stories);
        var inquiries = Read("Migrations", "062_service_contact_inquiries.sql");
        foreach (var clause in new[] { "FundingPlatform_fn_AdminAccessState", "FundingPlatform_usp_AdminActor_Lock", "@Hash<>@RequestHash", "NotificationStatus=0", "NotificationStatus=1", "sp_getapplock", ">=3", ">=500" }) Assert.Contains(clause, inquiries);
        Assert.DoesNotContain("GRANT SELECT", inquiries);
    }
    private static string Read(string folder, string file) => File.ReadAllText(Path.Combine(SolutionRootLocator.Find(AppContext.BaseDirectory), "database", folder, file));
    private sealed class Notifier(List<string> events) : IInquiryTeamNotifier
    {
        public bool Configured { get; init; } public bool Fail { get; init; } public int Calls { get; private set; }
        public Task SendAsync(Inquiry inquiry, CancellationToken token) { Calls++; events.Add("send"); if (Fail) throw new InquiryNotificationException(); return Task.CompletedTask; }
    }
    private sealed class Repository : IInquiryRepository
    {
        public readonly List<string> Events = []; public byte[]? Hash; public bool? Accepted; private InquiryInput? saved; private bool claimed;
        public Task<InquiryReceipt> CaptureAsync(InquiryInput d, byte[] hash, CancellationToken token) { Events.Add("capture"); var replay = saved != null; saved = d; Hash = hash; return Task.FromResult(new InquiryReceipt(d.RequestId, replay)); }
        public Task<Inquiry?> ClaimNotificationAsync(Guid id, CancellationToken token) { Events.Add("claim"); if (claimed) return Task.FromResult<Inquiry?>(null); claimed = true; return Task.FromResult<Inquiry?>(new(id, saved!, "Chile", 0, 1, 1, DateTimeOffset.UtcNow)); }
        public Task FinishNotificationAsync(Guid id, bool accepted, CancellationToken token) { Events.Add("finish"); Accepted = accepted; return Task.CompletedTask; }
        public Task<InquiryPage> ListAsync(Guid actor, int page, CancellationToken token) => throw new NotSupportedException();
        public Task ReviewAsync(Guid actor, Guid id, InquiryReview data, CancellationToken token) => throw new NotSupportedException();
    }
}
