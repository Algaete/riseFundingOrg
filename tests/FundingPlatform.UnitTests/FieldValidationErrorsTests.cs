using FundingPlatform.Core.Validation;

namespace FundingPlatform.UnitTests;

public sealed class FieldValidationErrorsTests
{
    [Fact]
    public void Replacing_a_field_keeps_code_and_legacy_message_in_sync()
    {
        var errors = FieldValidationErrors.Single("title", "required", "Obligatorio.");
        errors.Set("TITLE", "text-max-length", "Admite hasta 250 caracteres.", max: 250);

        Assert.Single(errors);
        Assert.Equal("Admite hasta 250 caracteres.", Assert.Single(errors["title"]));
        Assert.Equal(new FieldValidationIssue("text-max-length", Max: 250), Assert.Single(errors.Issues["title"]));
        Assert.True(errors.TryGetValue("TITLE", out var messages));
        Assert.Equal(errors["title"], messages);
        Assert.False(errors.TryGetValue("missing", out var missing));
        Assert.Empty(missing);
        Assert.Equal(errors["title"], Assert.Single(errors).Value);
        Assert.Equal(errors["title"], Assert.Single(errors.Values));
    }

    [Fact]
    public void Consumers_cannot_mutate_the_stored_messages_or_issue_arrays()
    {
        var errors = FieldValidationErrors.Single("title", "required", "Obligatorio.");
        errors["title"][0] = "Changed";
        errors.Issues["title"][0] = new FieldValidationIssue("changed");
        Assert.Equal("Obligatorio.", errors["title"][0]);
        Assert.Equal("required", errors.Issues["title"][0].Code);
    }
}
