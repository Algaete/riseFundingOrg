/* Used only by the migrator verification callback inside its rollback transaction.
   No real accounts are reused; all rows share an unpredictable per-run tag.
   no-point intentionally models malformed legacy data (public consent without
   coordinates) to check the read guard, not a valid application write. */
SET NOCOUNT ON;
IF @@TRANCOUNT = 0 THROW 55893, N'Map fixtures require a rollback transaction.', 1;
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
DECLARE @Email NVARCHAR(320) = @Tag + N'@example.invalid';
INSERT dbo.FundingPlatform_Users
    (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp, EmailConfirmed, Status, PreferredLocale)
VALUES (NEWID(), @Email, UPPER(@Email), @Tag, N'not-a-credential', @Tag, 1, 2, N'es-CL');
DECLARE @UserId BIGINT = SCOPE_IDENTITY();
DECLARE @Organizations TABLE (Scenario NVARCHAR(30), PublicId UNIQUEIDENTIFIER);
INSERT @Organizations VALUES (N'main', NEWID()), (N'other', NEWID()), (N'inactive', NEWID()), (N'unready', NEWID());
INSERT dbo.FundingPlatform_Organizations
    (PublicId, CreatedByUserId, Name, HomeCountryId, OrganizationTypeId, ProfileStatus, ProfileCompleteness, IsActive)
SELECT PublicId, @UserId, @Tag + N'-' + Scenario, 152,
    CASE WHEN Scenario = N'other' THEN 1 ELSE 2 END,
    CASE WHEN Scenario = N'unready' THEN 0 ELSE 2 END, 100,
    CASE WHEN Scenario = N'inactive' THEN 0 ELSE 1 END FROM @Organizations;

DECLARE @Cases TABLE (Scenario NVARCHAR(30), PublicId UNIQUEIDENTIFIER, Org NVARCHAR(30),
    Budget DECIMAL(19,4), Confirmed DECIMAL(19,4), Currency CHAR(3), Visibility INT,
    Coordinates BIT, Partners BIT, Professionals BIT, Consortium BIT);
INSERT @Cases VALUES
 (N'usd', NEWID(), N'main', 100, 25, 'USD', 2, 1, 1, 1, 1),
 (N'zero', NEWID(), N'main', 100, 100, 'USD', 2, 1, 0, 0, 0),
 (N'eur', NEWID(), N'main', 100, 25, 'EUR', 2, 1, 1, 0, 0),
 (N'large', NEWID(), N'main', 1000.1234, 100, 'USD', 2, 1, 0, 1, 0),
 (N'other', NEWID(), N'other', 100, 25, 'USD', 2, 1, 0, 0, 1),
 (N'hidden', NEWID(), N'main', 100, 25, 'USD', 0, 1, 1, 1, 1),
 (N'no-point', NEWID(), N'main', 100, 25, 'USD', 2, 0, 1, 1, 1),
 (N'unknown', NEWID(), N'main', NULL, NULL, NULL, 2, 1, 1, 1, 1),
 (N'draft', NEWID(), N'main', 100, 25, 'USD', 2, 1, 1, 1, 1),
 (N'inactive-project', NEWID(), N'main', 100, 25, 'USD', 2, 1, 1, 1, 1),
 (N'inactive-org', NEWID(), N'inactive', 100, 25, 'USD', 2, 1, 1, 1, 1),
 (N'unready-org', NEWID(), N'unready', 100, 25, 'USD', 2, 1, 1, 1, 1);

INSERT dbo.FundingPlatform_Projects
    (PublicId, OrganizationId, CreatedByUserId, Slug, Title, Summary, Description,
     ProjectStatus, ProjectStage, PublicationStatus, BudgetTotal, ConfirmedFunding, Currency,
     EnrichmentJson, IsActive, CreatedAtUtc, UpdatedAtUtc, PublishedAtUtc, ReviewedAtUtc, ReviewedByUserId)
SELECT cases.PublicId, organizations.Id, @UserId, @Tag + N'-' + cases.Scenario,
    @Tag + N'-' + cases.Scenario, N'Synthetic map contract', N'Synthetic rollback-only project',
    CASE WHEN cases.Scenario = N'zero' THEN 4 ELSE 2 END,
    CASE WHEN cases.Scenario = N'zero' THEN 0 ELSE 1 END,
    CASE WHEN cases.Scenario = N'draft' THEN 0 ELSE 2 END,
    cases.Budget, cases.Confirmed, cases.Currency,
    (SELECT CASE WHEN cases.Coordinates = 1 THEN CAST(-33.456789 AS DECIMAL(12,6)) END AS latitude,
        CASE WHEN cases.Coordinates = 1 THEN CAST(-70.654321 AS DECIMAL(12,6)) END AS longitude,
        cases.Visibility AS locationVisibility,
        CASE WHEN cases.Partners = 1 THEN N'Municipios' END AS soughtPartners,
        CASE WHEN cases.Professionals = 1 THEN N'Ingenieros' END AS soughtProfessionals,
        cases.Consortium AS seekingConsortium FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    CASE WHEN cases.Scenario = N'inactive-project' THEN 0 ELSE 1 END,
    @Now, @Now, @Now, @Now, @UserId
FROM @Cases cases JOIN @Organizations names ON names.Scenario = cases.Org
JOIN dbo.FundingPlatform_Organizations organizations ON organizations.PublicId = names.PublicId;

INSERT dbo.FundingPlatform_ProjectCountries (ProjectId, CountryId)
SELECT projects.Id, CASE WHEN cases.Scenario = N'other' THEN 392 ELSE 152 END
FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
INSERT dbo.FundingPlatform_ProjectCategories (ProjectId, FundingCategoryId)
SELECT projects.Id, CASE WHEN cases.Scenario = N'other' THEN 2 ELSE 1 END
FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
INSERT dbo.FundingPlatform_ProjectBeneficiaryTypes (ProjectId, BeneficiaryTypeId)
SELECT projects.Id, 1 FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
INSERT dbo.FundingPlatform_ProjectProjectTypes (ProjectId, ProjectTypeId)
SELECT projects.Id, 1 FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
INSERT dbo.FundingPlatform_ProjectSustainableDevelopmentGoals (ProjectId, SustainableDevelopmentGoalId)
SELECT projects.Id, CASE WHEN cases.Scenario = N'zero' THEN 4 ELSE 13 END
FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
SELECT cases.Scenario, projects.Id, projects.PublicId, projects.OrganizationId
FROM @Cases cases JOIN dbo.FundingPlatform_Projects projects ON projects.PublicId = cases.PublicId;
