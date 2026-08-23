/*
    FundingPlatform - FASE 2 baseline

    Forward-only migration for Azure SQL. The DatabaseMigrator owns the
    transaction and dbo.FundingPlatform_SchemaVersions. This script never
    drops or changes objects that do not belong to FundingPlatform.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* Catalogs */
CREATE TABLE dbo.FundingPlatform_Countries
(
    Id SMALLINT NOT NULL,
    Iso2 CHAR(2) NOT NULL,
    Iso3 CHAR(3) NOT NULL,
    Name NVARCHAR(120) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Countries_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Countries_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Countries_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Countries PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Countries_Iso2 UNIQUE (Iso2),
    CONSTRAINT FundingPlatform_UQ_Countries_Iso3 UNIQUE (Iso3)
);

CREATE TABLE dbo.FundingPlatform_Currencies
(
    Code CHAR(3) NOT NULL,
    Name NVARCHAR(120) NOT NULL,
    MinorUnits TINYINT NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Currencies_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Currencies_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Currencies_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Currencies PRIMARY KEY (Code),
    CONSTRAINT FundingPlatform_CK_Currencies_MinorUnits CHECK (MinorUnits BETWEEN 0 AND 4)
);

CREATE TABLE dbo.FundingPlatform_Regions
(
    Id INT NOT NULL,
    CountryId SMALLINT NOT NULL,
    Code NVARCHAR(20) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Regions_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Regions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Regions_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Regions PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_Regions_Countries FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_UQ_Regions_Country_Code UNIQUE (CountryId, Code)
);

CREATE INDEX FundingPlatform_IX_Regions_Country_Active_Name
    ON dbo.FundingPlatform_Regions (CountryId, IsActive, Name);

CREATE TABLE dbo.FundingPlatform_FundingCategories
(
    Id INT NOT NULL,
    ParentId INT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingCategories_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingCategories_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingCategories_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingCategories PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_FundingCategories_Parent FOREIGN KEY (ParentId)
        REFERENCES dbo.FundingPlatform_FundingCategories (Id),
    CONSTRAINT FundingPlatform_UQ_FundingCategories_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_OrganizationTypes
(
    Id SMALLINT NOT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationTypes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationTypes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationTypes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_OrganizationTypes_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_LegalEntityTypes
(
    Id SMALLINT NOT NULL,
    CountryId SMALLINT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_LegalEntityTypes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_LegalEntityTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_LegalEntityTypes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_LegalEntityTypes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_LegalEntityTypes_Countries FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_UQ_LegalEntityTypes_Country_Code UNIQUE (CountryId, Code)
);

CREATE TABLE dbo.FundingPlatform_OrganizationSizes
(
    Id SMALLINT NOT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    MinEmployees INT NULL,
    MaxEmployees INT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationSizes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationSizes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationSizes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationSizes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_OrganizationSizes_Code UNIQUE (Code),
    CONSTRAINT FundingPlatform_CK_OrganizationSizes_Range CHECK
        ((MinEmployees IS NULL OR MinEmployees >= 0)
         AND (MaxEmployees IS NULL OR MaxEmployees >= MinEmployees))
);

CREATE TABLE dbo.FundingPlatform_BeneficiaryTypes
(
    Id INT NOT NULL,
    ParentId INT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_BeneficiaryTypes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_BeneficiaryTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_BeneficiaryTypes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_BeneficiaryTypes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_BeneficiaryTypes_Parent FOREIGN KEY (ParentId)
        REFERENCES dbo.FundingPlatform_BeneficiaryTypes (Id),
    CONSTRAINT FundingPlatform_UQ_BeneficiaryTypes_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_FundingTypes
(
    Id SMALLINT NOT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingTypes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingTypes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingTypes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingTypes_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_ProjectTypes
(
    Id INT NOT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_ProjectTypes_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_ProjectTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_ProjectTypes_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_ProjectTypes PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_ProjectTypes_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_Tags
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    NormalizedName NVARCHAR(100) NOT NULL,
    IsApproved BIT NOT NULL CONSTRAINT FundingPlatform_DF_Tags_IsApproved DEFAULT (0),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Tags_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Tags_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Tags_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Tags PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Tags_NormalizedName UNIQUE (NormalizedName)
);

CREATE TABLE dbo.FundingPlatform_Languages
(
    Id SMALLINT NOT NULL,
    IsoCode NVARCHAR(10) NOT NULL,
    Name NVARCHAR(120) NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Languages_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Languages_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Languages_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Languages PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Languages_IsoCode UNIQUE (IsoCode)
);

/* Free plan and feature entitlements. Billing entities intentionally start in FASE 9. */
CREATE TABLE dbo.FundingPlatform_SubscriptionPlans
(
    Id SMALLINT NOT NULL,
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(120) NOT NULL,
    Description NVARCHAR(500) NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_IsActive DEFAULT (1),
    IsPublic BIT NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_IsPublic DEFAULT (1),
    IsPurchasable BIT NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_IsPurchasable DEFAULT (0),
    SortOrder SMALLINT NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_SortOrder DEFAULT (0),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlans_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_SubscriptionPlans PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_SubscriptionPlans_Code UNIQUE (Code)
);

CREATE TABLE dbo.FundingPlatform_Features
(
    Code NVARCHAR(100) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    Description NVARCHAR(500) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Features_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Features PRIMARY KEY (Code)
);

CREATE TABLE dbo.FundingPlatform_SubscriptionPlanFeatures
(
    SubscriptionPlanId SMALLINT NOT NULL,
    FeatureCode NVARCHAR(100) NOT NULL,
    IsEnabled BIT NOT NULL,
    LimitValue DECIMAL(19,4) NULL,
    Unit NVARCHAR(30) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_SubscriptionPlanFeatures_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_SubscriptionPlanFeatures PRIMARY KEY (SubscriptionPlanId, FeatureCode),
    CONSTRAINT FundingPlatform_FK_SubscriptionPlanFeatures_Plans FOREIGN KEY (SubscriptionPlanId)
        REFERENCES dbo.FundingPlatform_SubscriptionPlans (Id),
    CONSTRAINT FundingPlatform_FK_SubscriptionPlanFeatures_Features FOREIGN KEY (FeatureCode)
        REFERENCES dbo.FundingPlatform_Features (Code),
    CONSTRAINT FundingPlatform_CK_SubscriptionPlanFeatures_Limit CHECK (LimitValue IS NULL OR LimitValue >= 0)
);

/* Identity base. Session rotation and MFA tables are delivered with FASE 3. */
CREATE TABLE dbo.FundingPlatform_Users
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_Users_PublicId DEFAULT (NEWSEQUENTIALID()),
    Email NVARCHAR(320) NOT NULL,
    NormalizedEmail NVARCHAR(320) NOT NULL,
    DisplayName NVARCHAR(150) NOT NULL,
    PasswordHash NVARCHAR(1000) NULL,
    SecurityStamp NVARCHAR(100) NOT NULL,
    SecurityVersion INT NOT NULL CONSTRAINT FundingPlatform_DF_Users_SecurityVersion DEFAULT (1),
    EmailConfirmed BIT NOT NULL CONSTRAINT FundingPlatform_DF_Users_EmailConfirmed DEFAULT (0),
    TwoFactorEnabled BIT NOT NULL CONSTRAINT FundingPlatform_DF_Users_TwoFactorEnabled DEFAULT (0),
    Status TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Users_Status DEFAULT (0),
    AccessFailedCount INT NOT NULL CONSTRAINT FundingPlatform_DF_Users_AccessFailedCount DEFAULT (0),
    LockoutEndUtc DATETIME2(3) NULL,
    PreferredLocale NVARCHAR(10) NOT NULL CONSTRAINT FundingPlatform_DF_Users_PreferredLocale DEFAULT (N'es-CL'),
    LastLoginAtUtc DATETIME2(3) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Users_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Users_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_Users PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Users_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_Users_NormalizedEmail UNIQUE (NormalizedEmail),
    CONSTRAINT FundingPlatform_CK_Users_Status CHECK (Status BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_Users_SecurityVersion CHECK (SecurityVersion >= 1),
    CONSTRAINT FundingPlatform_CK_Users_AccessFailedCount CHECK (AccessFailedCount >= 0),
    CONSTRAINT FundingPlatform_CK_Users_PasswordState CHECK (PasswordHash IS NOT NULL OR Status = 0)
);

CREATE INDEX FundingPlatform_IX_Users_Status_CreatedAtUtc
    ON dbo.FundingPlatform_Users (Status, CreatedAtUtc);

CREATE TABLE dbo.FundingPlatform_Roles
(
    Id SMALLINT NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    NormalizedName NVARCHAR(100) NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Roles_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Roles_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_Roles PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Roles_NormalizedName UNIQUE (NormalizedName)
);

CREATE TABLE dbo.FundingPlatform_UserRoles
(
    UserId BIGINT NOT NULL,
    RoleId SMALLINT NOT NULL,
    GrantedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_UserRoles_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_UserRoles PRIMARY KEY (UserId, RoleId),
    CONSTRAINT FundingPlatform_FK_UserRoles_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_UserRoles_Roles FOREIGN KEY (RoleId)
        REFERENCES dbo.FundingPlatform_Roles (Id),
    CONSTRAINT FundingPlatform_FK_UserRoles_GrantedByUser FOREIGN KEY (GrantedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id)
);

/* Organization aggregate */
CREATE TABLE dbo.FundingPlatform_Organizations
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_PublicId DEFAULT (NEWSEQUENTIALID()),
    CreatedByUserId BIGINT NOT NULL,
    Name NVARCHAR(250) NOT NULL,
    LegalName NVARCHAR(300) NULL,
    TaxIdentifier NVARCHAR(50) NULL,
    HomeCountryId SMALLINT NOT NULL,
    OrganizationTypeId SMALLINT NOT NULL,
    LegalEntityTypeId SMALLINT NULL,
    OrganizationSizeId SMALLINT NULL,
    EstablishedYear SMALLINT NULL,
    WebsiteUrl NVARCHAR(2048) NULL,
    Description NVARCHAR(2000) NULL,
    PreviousFundingExperience TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_FundingExperience DEFAULT (0),
    ExperienceSummary NVARCHAR(2000) NULL,
    AnnualBudgetMin DECIMAL(19,4) NULL,
    AnnualBudgetMax DECIMAL(19,4) NULL,
    AnnualBudgetCurrency CHAR(3) NULL,
    DesiredFundingMin DECIMAL(19,4) NULL,
    DesiredFundingMax DECIMAL(19,4) NULL,
    DesiredFundingCurrency CHAR(3) NULL,
    ProfileStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_ProfileStatus DEFAULT (0),
    ProfileCompleteness DECIMAL(5,2) NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_ProfileCompleteness DEFAULT (0),
    ProfileVersion INT NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_ProfileVersion DEFAULT (1),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_Organizations_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_Organizations PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_Organizations_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_FK_Organizations_CreatedByUser FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_Organizations_HomeCountry FOREIGN KEY (HomeCountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_FK_Organizations_OrganizationType FOREIGN KEY (OrganizationTypeId)
        REFERENCES dbo.FundingPlatform_OrganizationTypes (Id),
    CONSTRAINT FundingPlatform_FK_Organizations_LegalEntityType FOREIGN KEY (LegalEntityTypeId)
        REFERENCES dbo.FundingPlatform_LegalEntityTypes (Id),
    CONSTRAINT FundingPlatform_FK_Organizations_OrganizationSize FOREIGN KEY (OrganizationSizeId)
        REFERENCES dbo.FundingPlatform_OrganizationSizes (Id),
    CONSTRAINT FundingPlatform_FK_Organizations_AnnualBudgetCurrency FOREIGN KEY (AnnualBudgetCurrency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_FK_Organizations_DesiredFundingCurrency FOREIGN KEY (DesiredFundingCurrency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_CK_Organizations_EstablishedYear CHECK (EstablishedYear IS NULL OR EstablishedYear BETWEEN 1800 AND 2200),
    CONSTRAINT FundingPlatform_CK_Organizations_FundingExperience CHECK (PreviousFundingExperience BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_Organizations_ProfileStatus CHECK (ProfileStatus BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_Organizations_ProfileCompleteness CHECK (ProfileCompleteness BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_Organizations_ProfileVersion CHECK (ProfileVersion >= 1),
    CONSTRAINT FundingPlatform_CK_Organizations_AnnualBudget CHECK
        ((AnnualBudgetMin IS NULL OR AnnualBudgetMin >= 0)
         AND (AnnualBudgetMax IS NULL OR AnnualBudgetMax >= AnnualBudgetMin)
         AND ((AnnualBudgetMin IS NULL AND AnnualBudgetMax IS NULL AND AnnualBudgetCurrency IS NULL)
              OR ((AnnualBudgetMin IS NOT NULL OR AnnualBudgetMax IS NOT NULL) AND AnnualBudgetCurrency IS NOT NULL))),
    CONSTRAINT FundingPlatform_CK_Organizations_DesiredFunding CHECK
        ((DesiredFundingMin IS NULL OR DesiredFundingMin >= 0)
         AND (DesiredFundingMax IS NULL OR DesiredFundingMax >= DesiredFundingMin)
         AND ((DesiredFundingMin IS NULL AND DesiredFundingMax IS NULL AND DesiredFundingCurrency IS NULL)
              OR ((DesiredFundingMin IS NOT NULL OR DesiredFundingMax IS NOT NULL) AND DesiredFundingCurrency IS NOT NULL)))
);

CREATE TABLE dbo.FundingPlatform_OrganizationUsers
(
    OrganizationId BIGINT NOT NULL,
    UserId BIGINT NOT NULL,
    Role TINYINT NOT NULL,
    MembershipStatus TINYINT NOT NULL,
    JoinedAtUtc DATETIME2(3) NULL,
    InvitedByUserId BIGINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationUsers_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationUsers_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationUsers PRIMARY KEY (OrganizationId, UserId),
    CONSTRAINT FundingPlatform_FK_OrganizationUsers_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationUsers_Users FOREIGN KEY (UserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationUsers_InvitedByUser FOREIGN KEY (InvitedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_OrganizationUsers_Role CHECK (Role IN (1, 2)),
    CONSTRAINT FundingPlatform_CK_OrganizationUsers_Status CHECK (MembershipStatus BETWEEN 0 AND 3),
    CONSTRAINT FundingPlatform_CK_OrganizationUsers_JoinedAt CHECK
        ((MembershipStatus = 0 AND JoinedAtUtc IS NULL) OR MembershipStatus <> 0)
);

CREATE INDEX FundingPlatform_IX_OrganizationUsers_User_Status
    ON dbo.FundingPlatform_OrganizationUsers (UserId, MembershipStatus)
    INCLUDE (OrganizationId, Role);

CREATE INDEX FundingPlatform_IX_OrganizationUsers_Organization_Status_Role
    ON dbo.FundingPlatform_OrganizationUsers (OrganizationId, MembershipStatus, Role);

CREATE TABLE dbo.FundingPlatform_OrganizationCountries
(
    OrganizationId BIGINT NOT NULL,
    CountryId SMALLINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationCountries_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationCountries PRIMARY KEY (OrganizationId, CountryId),
    CONSTRAINT FundingPlatform_FK_OrganizationCountries_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationCountries_Countries FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationCountries_Country
    ON dbo.FundingPlatform_OrganizationCountries (CountryId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationRegions
(
    OrganizationId BIGINT NOT NULL,
    RegionId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationRegions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationRegions PRIMARY KEY (OrganizationId, RegionId),
    CONSTRAINT FundingPlatform_FK_OrganizationRegions_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationRegions_Regions FOREIGN KEY (RegionId)
        REFERENCES dbo.FundingPlatform_Regions (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationRegions_Region
    ON dbo.FundingPlatform_OrganizationRegions (RegionId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationCategories
(
    OrganizationId BIGINT NOT NULL,
    FundingCategoryId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationCategories_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationCategories PRIMARY KEY (OrganizationId, FundingCategoryId),
    CONSTRAINT FundingPlatform_FK_OrganizationCategories_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationCategories_Categories FOREIGN KEY (FundingCategoryId)
        REFERENCES dbo.FundingPlatform_FundingCategories (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationCategories_Category
    ON dbo.FundingPlatform_OrganizationCategories (FundingCategoryId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationBeneficiaryTypes
(
    OrganizationId BIGINT NOT NULL,
    BeneficiaryTypeId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationBeneficiaryTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationBeneficiaryTypes PRIMARY KEY (OrganizationId, BeneficiaryTypeId),
    CONSTRAINT FundingPlatform_FK_OrganizationBeneficiaryTypes_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationBeneficiaryTypes_Beneficiaries FOREIGN KEY (BeneficiaryTypeId)
        REFERENCES dbo.FundingPlatform_BeneficiaryTypes (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationBeneficiaryTypes_Beneficiary
    ON dbo.FundingPlatform_OrganizationBeneficiaryTypes (BeneficiaryTypeId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationProjectTypes
(
    OrganizationId BIGINT NOT NULL,
    ProjectTypeId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationProjectTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationProjectTypes PRIMARY KEY (OrganizationId, ProjectTypeId),
    CONSTRAINT FundingPlatform_FK_OrganizationProjectTypes_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationProjectTypes_ProjectTypes FOREIGN KEY (ProjectTypeId)
        REFERENCES dbo.FundingPlatform_ProjectTypes (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationProjectTypes_ProjectType
    ON dbo.FundingPlatform_OrganizationProjectTypes (ProjectTypeId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationTags
(
    OrganizationId BIGINT NOT NULL,
    TagId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationTags_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationTags PRIMARY KEY (OrganizationId, TagId),
    CONSTRAINT FundingPlatform_FK_OrganizationTags_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationTags_Tags FOREIGN KEY (TagId)
        REFERENCES dbo.FundingPlatform_Tags (Id)
);

CREATE INDEX FundingPlatform_IX_OrganizationTags_Tag
    ON dbo.FundingPlatform_OrganizationTags (TagId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationLanguages
(
    OrganizationId BIGINT NOT NULL,
    LanguageId SMALLINT NOT NULL,
    Proficiency TINYINT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationLanguages_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationLanguages PRIMARY KEY (OrganizationId, LanguageId),
    CONSTRAINT FundingPlatform_FK_OrganizationLanguages_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_OrganizationLanguages_Languages FOREIGN KEY (LanguageId)
        REFERENCES dbo.FundingPlatform_Languages (Id),
    CONSTRAINT FundingPlatform_CK_OrganizationLanguages_Proficiency CHECK (Proficiency IS NULL OR Proficiency BETWEEN 1 AND 5)
);

CREATE INDEX FundingPlatform_IX_OrganizationLanguages_Language
    ON dbo.FundingPlatform_OrganizationLanguages (LanguageId, OrganizationId);

CREATE TABLE dbo.FundingPlatform_OrganizationProfileVersions
(
    OrganizationId BIGINT NOT NULL,
    ProfileVersion INT NOT NULL,
    SnapshotJson NVARCHAR(MAX) NOT NULL,
    ContentHash BINARY(32) NOT NULL,
    CreatedByUserId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OrganizationProfileVersions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_OrganizationProfileVersions PRIMARY KEY (OrganizationId, ProfileVersion),
    CONSTRAINT FundingPlatform_FK_OrganizationProfileVersions_Organizations FOREIGN KEY (OrganizationId)
        REFERENCES dbo.FundingPlatform_Organizations (Id),
    CONSTRAINT FundingPlatform_FK_OrganizationProfileVersions_Users FOREIGN KEY (CreatedByUserId)
        REFERENCES dbo.FundingPlatform_Users (Id),
    CONSTRAINT FundingPlatform_CK_OrganizationProfileVersions_Version CHECK (ProfileVersion >= 1),
    CONSTRAINT FundingPlatform_CK_OrganizationProfileVersions_Json CHECK (ISJSON(SnapshotJson) = 1)
);

/* Funding sources and canonical opportunities */
CREATE TABLE dbo.FundingPlatform_FundingSources
(
    Id INT IDENTITY(1,1) NOT NULL,
    Name NVARCHAR(150) NOT NULL,
    ProviderType TINYINT NOT NULL,
    BaseUrl NVARCHAR(2048) NULL,
    IsEnabled BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingSources_IsEnabled DEFAULT (1),
    ScheduleCron NVARCHAR(100) NULL,
    MinimumDelaySeconds INT NULL,
    UserAgent NVARCHAR(300) NULL,
    TermsUrl NVARCHAR(2048) NULL,
    TermsReviewedAtUtc DATETIME2(3) NULL,
    RobotsReviewedAtUtc DATETIME2(3) NULL,
    LastSuccessfulRunAtUtc DATETIME2(3) NULL,
    ConfigurationJson NVARCHAR(MAX) NULL,
    SecretReference NVARCHAR(300) NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingSources_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingSources_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingSources PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingSources_Name UNIQUE (Name),
    CONSTRAINT FundingPlatform_CK_FundingSources_ProviderType CHECK (ProviderType BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_FundingSources_MinimumDelay CHECK (MinimumDelaySeconds IS NULL OR MinimumDelaySeconds >= 0),
    CONSTRAINT FundingPlatform_CK_FundingSources_ConfigurationJson CHECK (ConfigurationJson IS NULL OR ISJSON(ConfigurationJson) = 1)
);

CREATE TABLE dbo.FundingPlatform_FundingOpportunities
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    PublicId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_PublicId DEFAULT (NEWSEQUENTIALID()),
    Slug NVARCHAR(320) NOT NULL,
    Title NVARCHAR(350) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    Summary NVARCHAR(2000) NULL,
    SponsorName NVARCHAR(300) NOT NULL,
    SponsorUrl NVARCHAR(2048) NULL,
    ApplicationUrl NVARCHAR(2048) NULL,
    IssuerCountryId SMALLINT NULL,
    FundingTypeId SMALLINT NULL,
    Currency CHAR(3) NULL,
    MinAmount DECIMAL(19,4) NULL,
    MaxAmount DECIMAL(19,4) NULL,
    AmountStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_AmountStatus DEFAULT (0),
    OpenDate DATE NULL,
    CloseDate DATE NULL,
    CloseAtUtc DATETIME2(3) NULL,
    DeadlineTimeZoneId NVARCHAR(100) NULL,
    DeadlineType TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_DeadlineType DEFAULT (0),
    DeadlinePrecision TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_DeadlinePrecision DEFAULT (0),
    EligibilityDescription NVARCHAR(MAX) NULL,
    Requirements NVARCHAR(MAX) NULL,
    Objectives NVARCHAR(MAX) NULL,
    AllowedActivities NVARCHAR(MAX) NULL,
    ExcludedActivities NVARCHAR(MAX) NULL,
    Restrictions NVARCHAR(MAX) NULL,
    TargetOrganizationsDescription NVARCHAR(2000) NULL,
    TargetPopulationsDescription NVARCHAR(2000) NULL,
    MinimumOperatingYears SMALLINT NULL,
    RequiresLegalEntity BIT NULL,
    RequiresPriorExperience BIT NULL,
    RequiresCofunding BIT NULL,
    CofundingPercentage DECIMAL(5,2) NULL,
    GeographicScope TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_GeographicScope DEFAULT (0),
    RemoteApplication TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_RemoteApplication DEFAULT (0),
    PublicationStatus TINYINT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_PublicationStatus DEFAULT (0),
    PublishedAtUtc DATETIME2(3) NULL,
    LastVerifiedAtUtc DATETIME2(3) NULL,
    DataQualityScore DECIMAL(5,2) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_DataQualityScore DEFAULT (0),
    ContentVersion INT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_ContentVersion DEFAULT (1),
    ContentFingerprint BINARY(32) NULL,
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_IsActive DEFAULT (1),
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    UpdatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunities_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
    RowVersion ROWVERSION NOT NULL,
    CONSTRAINT FundingPlatform_PK_FundingOpportunities PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunities_PublicId UNIQUE (PublicId),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunities_Slug UNIQUE (Slug),
    CONSTRAINT FundingPlatform_FK_FundingOpportunities_IssuerCountry FOREIGN KEY (IssuerCountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunities_FundingType FOREIGN KEY (FundingTypeId)
        REFERENCES dbo.FundingPlatform_FundingTypes (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunities_Currency FOREIGN KEY (Currency)
        REFERENCES dbo.FundingPlatform_Currencies (Code),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_AmountStatus CHECK (AmountStatus BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_Amounts CHECK
        ((AmountStatus = 1 AND Currency IS NOT NULL AND (MinAmount IS NOT NULL OR MaxAmount IS NOT NULL)
          AND (MinAmount IS NULL OR MinAmount >= 0)
          AND (MaxAmount IS NULL OR MaxAmount >= COALESCE(MinAmount, 0)))
         OR (AmountStatus IN (0, 2) AND Currency IS NULL AND MinAmount IS NULL AND MaxAmount IS NULL)),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_DeadlineEnums CHECK
        (DeadlineType BETWEEN 0 AND 2 AND DeadlinePrecision BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_Deadline CHECK
        ((DeadlineType = 0 AND DeadlinePrecision = 0 AND CloseAtUtc IS NULL)
         OR (DeadlineType = 2 AND DeadlinePrecision = 0 AND CloseDate IS NULL AND CloseAtUtc IS NULL)
         OR (DeadlineType = 1 AND DeadlinePrecision = 1 AND CloseDate IS NOT NULL AND CloseAtUtc IS NULL)
         OR (DeadlineType = 1 AND DeadlinePrecision = 2 AND CloseDate IS NOT NULL
             AND CloseAtUtc IS NOT NULL AND DeadlineTimeZoneId IS NOT NULL)),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_DateRange CHECK
        (OpenDate IS NULL OR CloseDate IS NULL OR OpenDate <= CloseDate),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_MinimumOperatingYears CHECK
        (MinimumOperatingYears IS NULL OR MinimumOperatingYears >= 0),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_Cofunding CHECK
        ((CofundingPercentage IS NULL AND RequiresCofunding IS NULL)
         OR (RequiresCofunding = 0 AND (CofundingPercentage IS NULL OR CofundingPercentage = 0))
         OR (RequiresCofunding = 1 AND CofundingPercentage > 0 AND CofundingPercentage <= 100)),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_GeographicScope CHECK (GeographicScope BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_RemoteApplication CHECK (RemoteApplication BETWEEN 0 AND 2),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_PublicationStatus CHECK (PublicationStatus BETWEEN 0 AND 4),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_DataQualityScore CHECK (DataQualityScore BETWEEN 0 AND 100),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_ContentVersion CHECK (ContentVersion >= 1),
    CONSTRAINT FundingPlatform_CK_FundingOpportunities_PublishedAt CHECK
        ((PublicationStatus = 2 AND PublishedAtUtc IS NOT NULL) OR PublicationStatus <> 2)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunities_Published
    ON dbo.FundingPlatform_FundingOpportunities (PublicationStatus, IsActive, CloseDate, Id)
    INCLUDE (Title, SponsorName, MinAmount, MaxAmount, Currency, FundingTypeId)
    WHERE PublicationStatus = 2 AND IsActive = 1;

CREATE INDEX FundingPlatform_IX_FundingOpportunities_Deadline
    ON dbo.FundingPlatform_FundingOpportunities (CloseDate, Id)
    WHERE PublicationStatus = 2 AND IsActive = 1 AND CloseDate IS NOT NULL;

CREATE TABLE dbo.FundingPlatform_FundingOpportunityCategories
(
    FundingOpportunityId BIGINT NOT NULL,
    FundingCategoryId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityCategories_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityCategories PRIMARY KEY (FundingOpportunityId, FundingCategoryId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityCategories_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityCategories_Category FOREIGN KEY (FundingCategoryId)
        REFERENCES dbo.FundingPlatform_FundingCategories (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityCategories_Category
    ON dbo.FundingPlatform_FundingOpportunityCategories (FundingCategoryId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityCountries
(
    FundingOpportunityId BIGINT NOT NULL,
    CountryId SMALLINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityCountries_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityCountries PRIMARY KEY (FundingOpportunityId, CountryId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityCountries_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityCountries_Country FOREIGN KEY (CountryId)
        REFERENCES dbo.FundingPlatform_Countries (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityCountries_Country
    ON dbo.FundingPlatform_FundingOpportunityCountries (CountryId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityRegions
(
    FundingOpportunityId BIGINT NOT NULL,
    RegionId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityRegions_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityRegions PRIMARY KEY (FundingOpportunityId, RegionId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityRegions_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityRegions_Region FOREIGN KEY (RegionId)
        REFERENCES dbo.FundingPlatform_Regions (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityRegions_Region
    ON dbo.FundingPlatform_FundingOpportunityRegions (RegionId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityOrganizationTypes
(
    FundingOpportunityId BIGINT NOT NULL,
    OrganizationTypeId SMALLINT NOT NULL,
    EligibilityMode TINYINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityOrganizationTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityOrganizationTypes PRIMARY KEY (FundingOpportunityId, OrganizationTypeId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityOrganizationTypes_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityOrganizationTypes_Type FOREIGN KEY (OrganizationTypeId)
        REFERENCES dbo.FundingPlatform_OrganizationTypes (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityOrganizationTypes_Mode CHECK (EligibilityMode IN (1, 2))
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityOrganizationTypes_Type
    ON dbo.FundingPlatform_FundingOpportunityOrganizationTypes (OrganizationTypeId, EligibilityMode, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityLegalEntityTypes
(
    FundingOpportunityId BIGINT NOT NULL,
    LegalEntityTypeId SMALLINT NOT NULL,
    EligibilityMode TINYINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityLegalEntityTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityLegalEntityTypes PRIMARY KEY (FundingOpportunityId, LegalEntityTypeId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityLegalEntityTypes_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityLegalEntityTypes_Type FOREIGN KEY (LegalEntityTypeId)
        REFERENCES dbo.FundingPlatform_LegalEntityTypes (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityLegalEntityTypes_Mode CHECK (EligibilityMode IN (1, 2))
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityLegalEntityTypes_Type
    ON dbo.FundingPlatform_FundingOpportunityLegalEntityTypes (LegalEntityTypeId, EligibilityMode, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
(
    FundingOpportunityId BIGINT NOT NULL,
    BeneficiaryTypeId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityBeneficiaryTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityBeneficiaryTypes PRIMARY KEY (FundingOpportunityId, BeneficiaryTypeId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityBeneficiaryTypes_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityBeneficiaryTypes_Type FOREIGN KEY (BeneficiaryTypeId)
        REFERENCES dbo.FundingPlatform_BeneficiaryTypes (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityBeneficiaryTypes_Type
    ON dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes (BeneficiaryTypeId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityProjectTypes
(
    FundingOpportunityId BIGINT NOT NULL,
    ProjectTypeId INT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityProjectTypes_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityProjectTypes PRIMARY KEY (FundingOpportunityId, ProjectTypeId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityProjectTypes_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityProjectTypes_Type FOREIGN KEY (ProjectTypeId)
        REFERENCES dbo.FundingPlatform_ProjectTypes (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityProjectTypes_Type
    ON dbo.FundingPlatform_FundingOpportunityProjectTypes (ProjectTypeId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityTags
(
    FundingOpportunityId BIGINT NOT NULL,
    TagId BIGINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityTags_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityTags PRIMARY KEY (FundingOpportunityId, TagId),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityTags_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityTags_Tag FOREIGN KEY (TagId)
        REFERENCES dbo.FundingPlatform_Tags (Id)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityTags_Tag
    ON dbo.FundingPlatform_FundingOpportunityTags (TagId, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunityLanguages
(
    FundingOpportunityId BIGINT NOT NULL,
    LanguageId SMALLINT NOT NULL,
    LanguagePurpose TINYINT NOT NULL,
    CreatedAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunityLanguages_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT FundingPlatform_PK_FundingOpportunityLanguages PRIMARY KEY (FundingOpportunityId, LanguageId, LanguagePurpose),
    CONSTRAINT FundingPlatform_FK_FundingOpportunityLanguages_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id) ON DELETE CASCADE,
    CONSTRAINT FundingPlatform_FK_FundingOpportunityLanguages_Language FOREIGN KEY (LanguageId)
        REFERENCES dbo.FundingPlatform_Languages (Id),
    CONSTRAINT FundingPlatform_CK_FundingOpportunityLanguages_Purpose CHECK (LanguagePurpose BETWEEN 1 AND 3)
);

CREATE INDEX FundingPlatform_IX_FundingOpportunityLanguages_Language
    ON dbo.FundingPlatform_FundingOpportunityLanguages (LanguageId, LanguagePurpose, FundingOpportunityId);

CREATE TABLE dbo.FundingPlatform_FundingOpportunitySourceLinks
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    FundingOpportunityId BIGINT NOT NULL,
    FundingSourceId INT NOT NULL,
    ExternalId NVARCHAR(250) NULL,
    SourceItemKeyHash BINARY(32) NOT NULL,
    SourceUrl NVARCHAR(2048) NULL,
    CanonicalUrlHash BINARY(32) NULL,
    FirstSeenAtUtc DATETIME2(3) NOT NULL,
    LastSeenAtUtc DATETIME2(3) NOT NULL,
    IsPrimary BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunitySourceLinks_IsPrimary DEFAULT (0),
    IsActive BIT NOT NULL CONSTRAINT FundingPlatform_DF_FundingOpportunitySourceLinks_IsActive DEFAULT (1),
    CONSTRAINT FundingPlatform_PK_FundingOpportunitySourceLinks PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunitySourceLinks_Opportunity FOREIGN KEY (FundingOpportunityId)
        REFERENCES dbo.FundingPlatform_FundingOpportunities (Id),
    CONSTRAINT FundingPlatform_FK_FundingOpportunitySourceLinks_Source FOREIGN KEY (FundingSourceId)
        REFERENCES dbo.FundingPlatform_FundingSources (Id),
    CONSTRAINT FundingPlatform_UQ_FundingOpportunitySourceLinks_SourceKey UNIQUE (FundingSourceId, SourceItemKeyHash),
    CONSTRAINT FundingPlatform_CK_FundingOpportunitySourceLinks_SeenRange CHECK (LastSeenAtUtc >= FirstSeenAtUtc)
);

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingOpportunitySourceLinks_ExternalId
    ON dbo.FundingPlatform_FundingOpportunitySourceLinks (FundingSourceId, ExternalId)
    WHERE ExternalId IS NOT NULL;

CREATE UNIQUE INDEX FundingPlatform_UQ_FundingOpportunitySourceLinks_Primary
    ON dbo.FundingPlatform_FundingOpportunitySourceLinks (FundingOpportunityId)
    WHERE IsPrimary = 1 AND IsActive = 1;

CREATE INDEX FundingPlatform_IX_FundingOpportunitySourceLinks_CanonicalUrl
    ON dbo.FundingPlatform_FundingOpportunitySourceLinks (FundingSourceId, CanonicalUrlHash)
    WHERE CanonicalUrlHash IS NOT NULL;

/* Transactional outbox: payloads contain only safe identifiers and versions. */
CREATE TABLE dbo.FundingPlatform_OutboxMessages
(
    Id BIGINT IDENTITY(1,1) NOT NULL,
    MessageId UNIQUEIDENTIFIER NOT NULL CONSTRAINT FundingPlatform_DF_OutboxMessages_MessageId DEFAULT (NEWSEQUENTIALID()),
    MessageType NVARCHAR(100) NOT NULL,
    AggregateType NVARCHAR(100) NOT NULL,
    AggregateId NVARCHAR(100) NOT NULL,
    PayloadJson NVARCHAR(MAX) NOT NULL,
    OccurredAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OutboxMessages_OccurredAtUtc DEFAULT (SYSUTCDATETIME()),
    AvailableAtUtc DATETIME2(3) NOT NULL CONSTRAINT FundingPlatform_DF_OutboxMessages_AvailableAtUtc DEFAULT (SYSUTCDATETIME()),
    DispatchedAtUtc DATETIME2(3) NULL,
    AttemptCount SMALLINT NOT NULL CONSTRAINT FundingPlatform_DF_OutboxMessages_AttemptCount DEFAULT (0),
    LeaseOwner NVARCHAR(100) NULL,
    LeaseUntilUtc DATETIME2(3) NULL,
    LastError NVARCHAR(2000) NULL,
    CONSTRAINT FundingPlatform_PK_OutboxMessages PRIMARY KEY (Id),
    CONSTRAINT FundingPlatform_UQ_OutboxMessages_MessageId UNIQUE (MessageId),
    CONSTRAINT FundingPlatform_CK_OutboxMessages_PayloadJson CHECK (ISJSON(PayloadJson) = 1),
    CONSTRAINT FundingPlatform_CK_OutboxMessages_AttemptCount CHECK (AttemptCount >= 0),
    CONSTRAINT FundingPlatform_CK_OutboxMessages_Lease CHECK
        ((LeaseOwner IS NULL AND LeaseUntilUtc IS NULL) OR (LeaseOwner IS NOT NULL AND LeaseUntilUtc IS NOT NULL))
);

CREATE INDEX FundingPlatform_IX_OutboxMessages_Available
    ON dbo.FundingPlatform_OutboxMessages (AvailableAtUtc, Id)
    WHERE DispatchedAtUtc IS NULL;

/* Deterministic, insert-only seed. Existing catalog rows are never overwritten. */
INSERT INTO dbo.FundingPlatform_Countries (Id, Iso2, Iso3, Name)
SELECT Seed.Id, Seed.Iso2, Seed.Iso3, Seed.Name
FROM (VALUES
    (CAST(152 AS SMALLINT), CAST('CL' AS CHAR(2)), CAST('CHL' AS CHAR(3)), N'Chile')
) AS Seed (Id, Iso2, Iso3, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Countries AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_Currencies (Code, Name, MinorUnits)
SELECT Seed.Code, Seed.Name, Seed.MinorUnits
FROM (VALUES
    (CAST('CLP' AS CHAR(3)), N'Peso chileno', CAST(0 AS TINYINT)),
    (CAST('USD' AS CHAR(3)), N'Dólar estadounidense', CAST(2 AS TINYINT)),
    (CAST('EUR' AS CHAR(3)), N'Euro', CAST(2 AS TINYINT))
) AS Seed (Code, Name, MinorUnits)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Currencies AS Existing WHERE Existing.Code = Seed.Code
);

INSERT INTO dbo.FundingPlatform_Regions (Id, CountryId, Code, Name)
SELECT Seed.Id, Seed.CountryId, Seed.Code, Seed.Name
FROM (VALUES
    (1,  CAST(152 AS SMALLINT), N'CL-AP', N'Arica y Parinacota'),
    (2,  CAST(152 AS SMALLINT), N'CL-TA', N'Tarapacá'),
    (3,  CAST(152 AS SMALLINT), N'CL-AN', N'Antofagasta'),
    (4,  CAST(152 AS SMALLINT), N'CL-AT', N'Atacama'),
    (5,  CAST(152 AS SMALLINT), N'CL-CO', N'Coquimbo'),
    (6,  CAST(152 AS SMALLINT), N'CL-VS', N'Valparaíso'),
    (7,  CAST(152 AS SMALLINT), N'CL-RM', N'Metropolitana de Santiago'),
    (8,  CAST(152 AS SMALLINT), N'CL-LI', N'Libertador General Bernardo O''Higgins'),
    (9,  CAST(152 AS SMALLINT), N'CL-ML', N'Maule'),
    (10, CAST(152 AS SMALLINT), N'CL-NB', N'Ñuble'),
    (11, CAST(152 AS SMALLINT), N'CL-BI', N'Biobío'),
    (12, CAST(152 AS SMALLINT), N'CL-AR', N'La Araucanía'),
    (13, CAST(152 AS SMALLINT), N'CL-LR', N'Los Ríos'),
    (14, CAST(152 AS SMALLINT), N'CL-LL', N'Los Lagos'),
    (15, CAST(152 AS SMALLINT), N'CL-AI', N'Aysén del General Carlos Ibáñez del Campo'),
    (16, CAST(152 AS SMALLINT), N'CL-MA', N'Magallanes y de la Antártica Chilena')
) AS Seed (Id, CountryId, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Regions AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_FundingCategories (Id, ParentId, Code, Name)
SELECT Seed.Id, Seed.ParentId, Seed.Code, Seed.Name
FROM (VALUES
    (1, CAST(NULL AS INT), N'ENVIRONMENT', N'Medio ambiente'),
    (2, CAST(NULL AS INT), N'EDUCATION', N'Educación'),
    (3, CAST(NULL AS INT), N'SOCIAL_DEVELOPMENT', N'Desarrollo social'),
    (4, CAST(NULL AS INT), N'HEALTH', N'Salud'),
    (5, CAST(NULL AS INT), N'CULTURE', N'Cultura y patrimonio'),
    (6, CAST(NULL AS INT), N'HUMAN_RIGHTS', N'Derechos humanos'),
    (7, CAST(NULL AS INT), N'ECONOMIC_DEVELOPMENT', N'Desarrollo económico local'),
    (8, CAST(NULL AS INT), N'INNOVATION', N'Innovación y tecnología')
) AS Seed (Id, ParentId, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingCategories AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_OrganizationTypes (Id, Code, Name)
SELECT Seed.Id, Seed.Code, Seed.Name
FROM (VALUES
    (CAST(1 AS SMALLINT), N'NGO', N'Organización no gubernamental'),
    (CAST(2 AS SMALLINT), N'FOUNDATION', N'Fundación'),
    (CAST(3 AS SMALLINT), N'CORPORATION', N'Corporación'),
    (CAST(4 AS SMALLINT), N'COMMUNITY_ORGANIZATION', N'Organización comunitaria'),
    (CAST(5 AS SMALLINT), N'OTHER_NONPROFIT', N'Otra organización sin fines de lucro')
) AS Seed (Id, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_OrganizationTypes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_LegalEntityTypes (Id, CountryId, Code, Name)
SELECT Seed.Id, Seed.CountryId, Seed.Code, Seed.Name
FROM (VALUES
    (CAST(1 AS SMALLINT), CAST(152 AS SMALLINT), N'CL_FOUNDATION', N'Fundación'),
    (CAST(2 AS SMALLINT), CAST(152 AS SMALLINT), N'CL_CORPORATION', N'Corporación'),
    (CAST(3 AS SMALLINT), CAST(152 AS SMALLINT), N'CL_COMMUNITY_ORGANIZATION', N'Organización comunitaria funcional o territorial'),
    (CAST(4 AS SMALLINT), CAST(152 AS SMALLINT), N'CL_OTHER_NONPROFIT', N'Otra persona jurídica sin fines de lucro')
) AS Seed (Id, CountryId, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_LegalEntityTypes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_OrganizationSizes (Id, Code, Name, MinEmployees, MaxEmployees)
SELECT Seed.Id, Seed.Code, Seed.Name, Seed.MinEmployees, Seed.MaxEmployees
FROM (VALUES
    (CAST(1 AS SMALLINT), N'MICRO', N'Micro', 0, 9),
    (CAST(2 AS SMALLINT), N'SMALL', N'Pequeña', 10, 49),
    (CAST(3 AS SMALLINT), N'MEDIUM', N'Mediana', 50, 199),
    (CAST(4 AS SMALLINT), N'LARGE', N'Grande', 200, CAST(NULL AS INT))
) AS Seed (Id, Code, Name, MinEmployees, MaxEmployees)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_OrganizationSizes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_BeneficiaryTypes (Id, ParentId, Code, Name)
SELECT Seed.Id, Seed.ParentId, Seed.Code, Seed.Name
FROM (VALUES
    (1, CAST(NULL AS INT), N'CHILDREN', N'Niños, niñas y adolescentes'),
    (2, CAST(NULL AS INT), N'YOUTH', N'Jóvenes'),
    (3, CAST(NULL AS INT), N'OLDER_ADULTS', N'Personas mayores'),
    (4, CAST(NULL AS INT), N'WOMEN', N'Mujeres'),
    (5, CAST(NULL AS INT), N'PEOPLE_WITH_DISABILITIES', N'Personas con discapacidad'),
    (6, CAST(NULL AS INT), N'INDIGENOUS_PEOPLES', N'Pueblos indígenas'),
    (7, CAST(NULL AS INT), N'MIGRANTS', N'Personas migrantes y refugiadas'),
    (8, CAST(NULL AS INT), N'COMMUNITIES', N'Comunidades y organizaciones territoriales')
) AS Seed (Id, ParentId, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_BeneficiaryTypes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_FundingTypes (Id, Code, Name)
SELECT Seed.Id, Seed.Code, Seed.Name
FROM (VALUES
    (CAST(1 AS SMALLINT), N'GRANT', N'Subvención'),
    (CAST(2 AS SMALLINT), N'AWARD', N'Premio'),
    (CAST(3 AS SMALLINT), N'FELLOWSHIP', N'Beca'),
    (CAST(4 AS SMALLINT), N'TECHNICAL_ASSISTANCE', N'Asistencia técnica'),
    (CAST(5 AS SMALLINT), N'IN_KIND', N'Aporte en especie')
) AS Seed (Id, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_FundingTypes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_ProjectTypes (Id, Code, Name)
SELECT Seed.Id, Seed.Code, Seed.Name
FROM (VALUES
    (1, N'PROGRAM', N'Programa'),
    (2, N'RESEARCH', N'Investigación'),
    (3, N'INFRASTRUCTURE', N'Infraestructura'),
    (4, N'CAPACITY_BUILDING', N'Fortalecimiento institucional'),
    (5, N'ADVOCACY', N'Incidencia'),
    (6, N'EMERGENCY_RESPONSE', N'Respuesta a emergencias')
) AS Seed (Id, Code, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_ProjectTypes AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_Languages (Id, IsoCode, Name)
SELECT Seed.Id, Seed.IsoCode, Seed.Name
FROM (VALUES
    (CAST(1 AS SMALLINT), N'es', N'Español'),
    (CAST(2 AS SMALLINT), N'en', N'Inglés')
) AS Seed (Id, IsoCode, Name)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Languages AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_SubscriptionPlans
    (Id, Code, Name, Description, IsActive, IsPublic, IsPurchasable, SortOrder)
SELECT Seed.Id, Seed.Code, Seed.Name, Seed.Description, Seed.IsActive, Seed.IsPublic, Seed.IsPurchasable, Seed.SortOrder
FROM (VALUES
    (CAST(1 AS SMALLINT), N'FREE', N'Free', N'Plan gratuito inicial para validar el MVP.',
     CAST(1 AS BIT), CAST(1 AS BIT), CAST(0 AS BIT), CAST(10 AS SMALLINT))
) AS Seed (Id, Code, Name, Description, IsActive, IsPublic, IsPurchasable, SortOrder)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_SubscriptionPlans AS Existing WHERE Existing.Id = Seed.Id
);

INSERT INTO dbo.FundingPlatform_Features (Code, Name, Description)
SELECT Seed.Code, Seed.Name, Seed.Description
FROM (VALUES
    (N'funding.visible_limit', N'Límite de fondos visibles', N'Máximo de oportunidades visibles en el plan.'),
    (N'search.advanced', N'Búsqueda avanzada', N'Habilita filtros avanzados.'),
    (N'recommendations.enabled', N'Recomendaciones', N'Habilita recomendaciones de fondos.'),
    (N'alerts.max', N'Límite de alertas', N'Máximo de alertas activas.'),
    (N'ai.explanations_monthly', N'Explicaciones IA', N'Límite mensual de explicaciones generadas.'),
    (N'applications.enabled', N'Seguimiento de postulaciones', N'Habilita seguimiento básico de postulaciones.'),
    (N'calendar.enabled', N'Calendario', N'Habilita calendario interno de fechas.'),
    (N'organization.members_max', N'Miembros por organización', N'Máximo de miembros activos.'),
    (N'organizations.max_owned', N'Organizaciones propias', N'Máximo de organizaciones creadas por usuario.'),
    (N'export.enabled', N'Exportación', N'Habilita exportaciones de datos.')
) AS Seed (Code, Name, Description)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Features AS Existing WHERE Existing.Code = Seed.Code
);

INSERT INTO dbo.FundingPlatform_SubscriptionPlanFeatures
    (SubscriptionPlanId, FeatureCode, IsEnabled, LimitValue, Unit)
SELECT Seed.SubscriptionPlanId, Seed.FeatureCode, Seed.IsEnabled, Seed.LimitValue, Seed.Unit
FROM (VALUES
    (CAST(1 AS SMALLINT), N'funding.visible_limit', CAST(1 AS BIT), CAST(50 AS DECIMAL(19,4)), N'items'),
    (CAST(1 AS SMALLINT), N'search.advanced', CAST(0 AS BIT), CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30))),
    (CAST(1 AS SMALLINT), N'recommendations.enabled', CAST(1 AS BIT), CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30))),
    (CAST(1 AS SMALLINT), N'alerts.max', CAST(1 AS BIT), CAST(1 AS DECIMAL(19,4)), N'items'),
    (CAST(1 AS SMALLINT), N'ai.explanations_monthly', CAST(0 AS BIT), CAST(0 AS DECIMAL(19,4)), N'items/month'),
    (CAST(1 AS SMALLINT), N'applications.enabled', CAST(1 AS BIT), CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30))),
    (CAST(1 AS SMALLINT), N'calendar.enabled', CAST(1 AS BIT), CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30))),
    (CAST(1 AS SMALLINT), N'organization.members_max', CAST(1 AS BIT), CAST(3 AS DECIMAL(19,4)), N'items'),
    (CAST(1 AS SMALLINT), N'organizations.max_owned', CAST(1 AS BIT), CAST(1 AS DECIMAL(19,4)), N'items'),
    (CAST(1 AS SMALLINT), N'export.enabled', CAST(0 AS BIT), CAST(NULL AS DECIMAL(19,4)), CAST(NULL AS NVARCHAR(30)))
) AS Seed (SubscriptionPlanId, FeatureCode, IsEnabled, LimitValue, Unit)
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_SubscriptionPlanFeatures AS Existing
    WHERE Existing.SubscriptionPlanId = Seed.SubscriptionPlanId
      AND Existing.FeatureCode = Seed.FeatureCode
);

INSERT INTO dbo.FundingPlatform_Roles (Id, Name, NormalizedName)
SELECT Seed.Id, Seed.Name, Seed.NormalizedName
FROM (VALUES
    (CAST(1 AS SMALLINT), N'SuperAdmin', N'SUPERADMIN'),
    (CAST(2 AS SMALLINT), N'Admin', N'ADMIN')
) AS Seed (Id, Name, NormalizedName)
WHERE NOT EXISTS
(
    SELECT 1 FROM dbo.FundingPlatform_Roles AS Existing WHERE Existing.Id = Seed.Id
);

/* TVPs used by the aggregate procedures. Dynamic DDL avoids SQLCMD GO separators. */
EXEC sys.sp_executesql N'
CREATE TYPE dbo.FundingPlatform_SmallIntIdList AS TABLE
(
    Id SMALLINT NOT NULL,
    PRIMARY KEY (Id)
);';

EXEC sys.sp_executesql N'
CREATE TYPE dbo.FundingPlatform_IntIdList AS TABLE
(
    Id INT NOT NULL,
    PRIMARY KEY (Id)
);';

EXEC sys.sp_executesql N'
CREATE TYPE dbo.FundingPlatform_BigIntIdList AS TABLE
(
    Id BIGINT NOT NULL,
    PRIMARY KEY (Id)
);';

EXEC sys.sp_executesql N'
CREATE TYPE dbo.FundingPlatform_OrganizationLanguageList AS TABLE
(
    LanguageId SMALLINT NOT NULL,
    Proficiency TINYINT NULL,
    PRIMARY KEY (LanguageId),
    CHECK (Proficiency IS NULL OR Proficiency BETWEEN 1 AND 5)
);';

/* Organization procedures */
EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_Create
    @CreatedByUserId BIGINT,
    @Name NVARCHAR(250),
    @HomeCountryId SMALLINT,
    @OrganizationTypeId SMALLINT,
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@Name)), N'''') IS NULL
        THROW 51001, N''Organization name is required.'', 1;

    IF ISJSON(@SnapshotJson) <> 1
        THROW 51002, N''Initial profile snapshot must be valid JSON.'', 1;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @OrganizationId BIGINT;
    DECLARE @PayloadJson NVARCHAR(MAX);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION FundingPlatform_CreateOrg;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_Users WITH (UPDLOCK, HOLDLOCK)
            WHERE Id = @CreatedByUserId AND Status = 2
        )
            THROW 51003, N''The organization owner is not an active user.'', 1;

        INSERT INTO dbo.FundingPlatform_Organizations
            (CreatedByUserId, Name, HomeCountryId, OrganizationTypeId, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@CreatedByUserId, LTRIM(RTRIM(@Name)), @HomeCountryId, @OrganizationTypeId, @NowUtc, @NowUtc);

        SET @OrganizationId = CONVERT(BIGINT, SCOPE_IDENTITY());

        INSERT INTO dbo.FundingPlatform_OrganizationUsers
            (OrganizationId, UserId, Role, MembershipStatus, JoinedAtUtc, CreatedAtUtc, UpdatedAtUtc)
        VALUES
            (@OrganizationId, @CreatedByUserId, 1, 1, @NowUtc, @NowUtc, @NowUtc);

        INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
            (OrganizationId, ProfileVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES
            (@OrganizationId, 1, @SnapshotJson, @ContentHash, @CreatedByUserId, @NowUtc);

        SELECT @PayloadJson =
        (
            SELECT @OrganizationId AS organizationId, 1 AS profileVersion
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        VALUES
            (N''OrganizationCreated'', N''Organization'', CONVERT(NVARCHAR(100), @OrganizationId),
             @PayloadJson, @NowUtc, @NowUtc);

        IF @InitialTransactionCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_CreateOrg;
        THROW;
    END CATCH;

    SELECT Id, PublicId, ProfileVersion, RowVersion
    FROM dbo.FundingPlatform_Organizations
    WHERE Id = @OrganizationId;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_GetProfile
    @OrganizationId BIGINT,
    @UserId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION FundingPlatform_GetProfile;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_OrganizationUsers WITH (UPDLOCK, HOLDLOCK)
            WHERE OrganizationId = @OrganizationId
              AND UserId = @UserId
              AND MembershipStatus = 1
        )
            THROW 51003, N''Active organization membership is required.'', 1;

        SELECT
            o.Id, o.PublicId, o.CreatedByUserId, o.Name, o.LegalName, o.TaxIdentifier,
            o.HomeCountryId, o.OrganizationTypeId, o.LegalEntityTypeId, o.OrganizationSizeId,
            o.EstablishedYear, o.WebsiteUrl, o.Description, o.PreviousFundingExperience,
            o.ExperienceSummary, o.AnnualBudgetMin, o.AnnualBudgetMax, o.AnnualBudgetCurrency,
            o.DesiredFundingMin, o.DesiredFundingMax, o.DesiredFundingCurrency,
            o.ProfileStatus, o.ProfileCompleteness, o.ProfileVersion, o.IsActive,
            o.CreatedAtUtc, o.UpdatedAtUtc, o.RowVersion
        FROM dbo.FundingPlatform_Organizations AS o
        WHERE o.Id = @OrganizationId;

        SELECT CountryId AS Id
        FROM dbo.FundingPlatform_OrganizationCountries
        WHERE OrganizationId = @OrganizationId
        ORDER BY CountryId;

        SELECT RegionId AS Id
        FROM dbo.FundingPlatform_OrganizationRegions
        WHERE OrganizationId = @OrganizationId
        ORDER BY RegionId;

        SELECT FundingCategoryId AS Id
        FROM dbo.FundingPlatform_OrganizationCategories
        WHERE OrganizationId = @OrganizationId
        ORDER BY FundingCategoryId;

        SELECT BeneficiaryTypeId AS Id
        FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes
        WHERE OrganizationId = @OrganizationId
        ORDER BY BeneficiaryTypeId;

        SELECT ProjectTypeId AS Id
        FROM dbo.FundingPlatform_OrganizationProjectTypes
        WHERE OrganizationId = @OrganizationId
        ORDER BY ProjectTypeId;

        SELECT TagId AS Id
        FROM dbo.FundingPlatform_OrganizationTags
        WHERE OrganizationId = @OrganizationId
        ORDER BY TagId;

        SELECT LanguageId, Proficiency
        FROM dbo.FundingPlatform_OrganizationLanguages
        WHERE OrganizationId = @OrganizationId
        ORDER BY LanguageId;

        IF @InitialTransactionCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_GetProfile;
        THROW;
    END CATCH;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Organization_UpdateProfile
    @OrganizationId BIGINT,
    @ActorUserId BIGINT,
    @ExpectedRowVersion BINARY(8),
    @Name NVARCHAR(250),
    @LegalName NVARCHAR(300) = NULL,
    @TaxIdentifier NVARCHAR(50) = NULL,
    @HomeCountryId SMALLINT,
    @OrganizationTypeId SMALLINT,
    @LegalEntityTypeId SMALLINT = NULL,
    @OrganizationSizeId SMALLINT = NULL,
    @EstablishedYear SMALLINT = NULL,
    @WebsiteUrl NVARCHAR(2048) = NULL,
    @Description NVARCHAR(2000) = NULL,
    @PreviousFundingExperience TINYINT = 0,
    @ExperienceSummary NVARCHAR(2000) = NULL,
    @AnnualBudgetMin DECIMAL(19,4) = NULL,
    @AnnualBudgetMax DECIMAL(19,4) = NULL,
    @AnnualBudgetCurrency CHAR(3) = NULL,
    @DesiredFundingMin DECIMAL(19,4) = NULL,
    @DesiredFundingMax DECIMAL(19,4) = NULL,
    @DesiredFundingCurrency CHAR(3) = NULL,
    @ProfileStatus TINYINT,
    @ProfileCompleteness DECIMAL(5,2),
    @SnapshotJson NVARCHAR(MAX),
    @ContentHash BINARY(32),
    @CountryIds dbo.FundingPlatform_SmallIntIdList READONLY,
    @RegionIds dbo.FundingPlatform_IntIdList READONLY,
    @CategoryIds dbo.FundingPlatform_IntIdList READONLY,
    @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @ProjectTypeIds dbo.FundingPlatform_IntIdList READONLY,
    @TagIds dbo.FundingPlatform_BigIntIdList READONLY,
    @Languages dbo.FundingPlatform_OrganizationLanguageList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@Name)), N'''') IS NULL
        THROW 51004, N''Organization name is required.'', 1;

    IF ISJSON(@SnapshotJson) <> 1
        THROW 51005, N''Profile snapshot must be valid JSON.'', 1;

    DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @NextProfileVersion INT;
    DECLARE @PayloadJson NVARCHAR(MAX);
    DECLARE @InitialTransactionCount INT = @@TRANCOUNT;

    IF @InitialTransactionCount = 0
        BEGIN TRANSACTION;
    ELSE
        SAVE TRANSACTION FundingPlatform_UpdateProfile;

    BEGIN TRY
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.FundingPlatform_OrganizationUsers WITH (UPDLOCK, HOLDLOCK)
            WHERE OrganizationId = @OrganizationId
              AND UserId = @ActorUserId
              AND Role = 1
              AND MembershipStatus = 1
        )
            THROW 51006, N''Active organization administrator membership is required.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM @RegionIds AS SelectedRegion
            LEFT JOIN dbo.FundingPlatform_Regions AS Region WITH (HOLDLOCK)
                ON Region.Id = SelectedRegion.Id
            WHERE Region.Id IS NULL
        )
            THROW 51007, N''One or more selected regions do not exist.'', 1;

        IF EXISTS
        (
            SELECT 1
            FROM @RegionIds AS SelectedRegion
            INNER JOIN dbo.FundingPlatform_Regions AS Region WITH (HOLDLOCK)
                ON Region.Id = SelectedRegion.Id
            WHERE NOT EXISTS
            (
                SELECT 1 FROM @CountryIds AS SelectedCountry WHERE SelectedCountry.Id = Region.CountryId
            )
        )
            THROW 51010, N''Every selected region must belong to a selected operating country.'', 1;

        SELECT @NextProfileVersion = ProfileVersion + 1
        FROM dbo.FundingPlatform_Organizations WITH (UPDLOCK, HOLDLOCK)
        WHERE Id = @OrganizationId;

        IF @NextProfileVersion IS NULL
            THROW 51008, N''Organization was not found.'', 1;

        UPDATE dbo.FundingPlatform_Organizations
        SET Name = LTRIM(RTRIM(@Name)),
            LegalName = @LegalName,
            TaxIdentifier = @TaxIdentifier,
            HomeCountryId = @HomeCountryId,
            OrganizationTypeId = @OrganizationTypeId,
            LegalEntityTypeId = @LegalEntityTypeId,
            OrganizationSizeId = @OrganizationSizeId,
            EstablishedYear = @EstablishedYear,
            WebsiteUrl = @WebsiteUrl,
            Description = @Description,
            PreviousFundingExperience = @PreviousFundingExperience,
            ExperienceSummary = @ExperienceSummary,
            AnnualBudgetMin = @AnnualBudgetMin,
            AnnualBudgetMax = @AnnualBudgetMax,
            AnnualBudgetCurrency = @AnnualBudgetCurrency,
            DesiredFundingMin = @DesiredFundingMin,
            DesiredFundingMax = @DesiredFundingMax,
            DesiredFundingCurrency = @DesiredFundingCurrency,
            ProfileStatus = @ProfileStatus,
            ProfileCompleteness = @ProfileCompleteness,
            ProfileVersion = @NextProfileVersion,
            UpdatedAtUtc = @NowUtc
        WHERE Id = @OrganizationId
          AND RowVersion = @ExpectedRowVersion;

        IF @@ROWCOUNT = 0
            THROW 51009, N''Organization profile has a concurrency conflict.'', 1;

        DELETE FROM dbo.FundingPlatform_OrganizationCountries WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationRegions WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationCategories WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationBeneficiaryTypes WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationProjectTypes WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationTags WHERE OrganizationId = @OrganizationId;
        DELETE FROM dbo.FundingPlatform_OrganizationLanguages WHERE OrganizationId = @OrganizationId;

        INSERT INTO dbo.FundingPlatform_OrganizationCountries (OrganizationId, CountryId)
            SELECT @OrganizationId, Id FROM @CountryIds;
        INSERT INTO dbo.FundingPlatform_OrganizationRegions (OrganizationId, RegionId)
            SELECT @OrganizationId, Id FROM @RegionIds;
        INSERT INTO dbo.FundingPlatform_OrganizationCategories (OrganizationId, FundingCategoryId)
            SELECT @OrganizationId, Id FROM @CategoryIds;
        INSERT INTO dbo.FundingPlatform_OrganizationBeneficiaryTypes (OrganizationId, BeneficiaryTypeId)
            SELECT @OrganizationId, Id FROM @BeneficiaryTypeIds;
        INSERT INTO dbo.FundingPlatform_OrganizationProjectTypes (OrganizationId, ProjectTypeId)
            SELECT @OrganizationId, Id FROM @ProjectTypeIds;
        INSERT INTO dbo.FundingPlatform_OrganizationTags (OrganizationId, TagId)
            SELECT @OrganizationId, Id FROM @TagIds;
        INSERT INTO dbo.FundingPlatform_OrganizationLanguages (OrganizationId, LanguageId, Proficiency)
            SELECT @OrganizationId, LanguageId, Proficiency FROM @Languages;

        INSERT INTO dbo.FundingPlatform_OrganizationProfileVersions
            (OrganizationId, ProfileVersion, SnapshotJson, ContentHash, CreatedByUserId, CreatedAtUtc)
        VALUES
            (@OrganizationId, @NextProfileVersion, @SnapshotJson, @ContentHash, @ActorUserId, @NowUtc);

        SELECT @PayloadJson =
        (
            SELECT @OrganizationId AS organizationId, @NextProfileVersion AS profileVersion
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO dbo.FundingPlatform_OutboxMessages
            (MessageType, AggregateType, AggregateId, PayloadJson, OccurredAtUtc, AvailableAtUtc)
        VALUES
            (N''OrganizationProfileChanged'', N''Organization'', CONVERT(NVARCHAR(100), @OrganizationId),
             @PayloadJson, @NowUtc, @NowUtc);

        IF @InitialTransactionCount = 0
            COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
            ROLLBACK TRANSACTION FundingPlatform_UpdateProfile;
        THROW;
    END CATCH;

    SELECT Id, PublicId, ProfileVersion, RowVersion
    FROM dbo.FundingPlatform_Organizations
    WHERE Id = @OrganizationId;
END;';

/* Funding read procedures. Mutating editorial workflows arrive in FASE 5. */
EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_GetById
    @FundingOpportunityId BIGINT,
    @IncludeUnpublished BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CanRead BIT = CASE WHEN EXISTS
    (
        SELECT 1
        FROM dbo.FundingPlatform_FundingOpportunities
        WHERE Id = @FundingOpportunityId
          AND (@IncludeUnpublished = 1 OR (PublicationStatus = 2 AND IsActive = 1))
    ) THEN 1 ELSE 0 END;

    SELECT
        f.Id, f.PublicId, f.Slug, f.Title, f.Description, f.Summary,
        f.SponsorName, f.SponsorUrl, f.ApplicationUrl, f.IssuerCountryId,
        f.FundingTypeId, f.Currency, f.MinAmount, f.MaxAmount, f.AmountStatus,
        f.OpenDate, f.CloseDate, f.CloseAtUtc, f.DeadlineTimeZoneId,
        f.DeadlineType, f.DeadlinePrecision, f.EligibilityDescription,
        f.Requirements, f.Objectives, f.AllowedActivities, f.ExcludedActivities,
        f.Restrictions, f.TargetOrganizationsDescription, f.TargetPopulationsDescription,
        f.MinimumOperatingYears, f.RequiresLegalEntity, f.RequiresPriorExperience,
        f.RequiresCofunding, f.CofundingPercentage, f.GeographicScope,
        f.RemoteApplication, f.PublicationStatus, f.PublishedAtUtc,
        f.LastVerifiedAtUtc, f.DataQualityScore, f.ContentVersion,
        f.ContentFingerprint, f.IsActive, f.CreatedAtUtc, f.UpdatedAtUtc, f.RowVersion
    FROM dbo.FundingPlatform_FundingOpportunities AS f
    WHERE f.Id = @FundingOpportunityId
      AND @CanRead = 1;

    SELECT FundingCategoryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCategories
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY FundingCategoryId;

    SELECT CountryId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityCountries
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY CountryId;

    SELECT RegionId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityRegions
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY RegionId;

    SELECT OrganizationTypeId AS Id, EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityOrganizationTypes
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY OrganizationTypeId;

    SELECT LegalEntityTypeId AS Id, EligibilityMode
    FROM dbo.FundingPlatform_FundingOpportunityLegalEntityTypes
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY LegalEntityTypeId;

    SELECT BeneficiaryTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityBeneficiaryTypes
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY BeneficiaryTypeId;

    SELECT ProjectTypeId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityProjectTypes
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY ProjectTypeId;

    SELECT TagId AS Id
    FROM dbo.FundingPlatform_FundingOpportunityTags
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY TagId;

    SELECT LanguageId, LanguagePurpose
    FROM dbo.FundingPlatform_FundingOpportunityLanguages
    WHERE FundingOpportunityId = @FundingOpportunityId AND @CanRead = 1
    ORDER BY LanguageId, LanguagePurpose;

    SELECT Id, FundingSourceId, ExternalId, SourceUrl, FirstSeenAtUtc, LastSeenAtUtc, IsPrimary
    FROM dbo.FundingPlatform_FundingOpportunitySourceLinks
    WHERE FundingOpportunityId = @FundingOpportunityId AND IsActive = 1 AND @CanRead = 1
    ORDER BY IsPrimary DESC, Id;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_FundingOpportunity_Search
    @Query NVARCHAR(300) = NULL,
    @CountryId SMALLINT = NULL,
    @FundingCategoryId INT = NULL,
    @FundingTypeId SMALLINT = NULL,
    @NowUtc DATETIME2(3),
    @OnlyOpen BIT = 1,
    @PageNumber INT = 1,
    @PageSize INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @PageNumber < 1
        THROW 51020, N''PageNumber must be at least 1.'', 1;
    IF @PageSize < 1 OR @PageSize > 100
        THROW 51021, N''PageSize must be between 1 and 100.'', 1;

    DECLARE @QueryLike NVARCHAR(302) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Query)), N'''') IS NULL
             THEN NULL ELSE N''%'' + LTRIM(RTRIM(@Query)) + N''%'' END;
    DECLARE @Offset INT = (@PageNumber - 1) * @PageSize;

    SELECT COUNT_BIG(1) AS TotalCount
    FROM dbo.FundingPlatform_FundingOpportunities AS f
    WHERE f.PublicationStatus = 2
      AND f.IsActive = 1
      AND (@QueryLike IS NULL
           OR f.Title LIKE @QueryLike
           OR f.SponsorName LIKE @QueryLike
           OR f.Summary LIKE @QueryLike)
      AND (@FundingTypeId IS NULL OR f.FundingTypeId = @FundingTypeId)
      AND (@FundingCategoryId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS fc
           WHERE fc.FundingOpportunityId = f.Id AND fc.FundingCategoryId = @FundingCategoryId))
      AND (@CountryId IS NULL OR f.GeographicScope = 2 OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS fco
           WHERE fco.FundingOpportunityId = f.Id AND fco.CountryId = @CountryId))
      AND (@OnlyOpen = 0
           OR f.DeadlineType = 0
           OR f.DeadlineType = 2
           OR (f.DeadlineType = 1 AND f.DeadlinePrecision = 1 AND f.CloseDate >= CONVERT(DATE, @NowUtc))
           OR (f.DeadlineType = 1 AND f.DeadlinePrecision = 2 AND f.CloseAtUtc >= @NowUtc));

    SELECT
        f.Id, f.PublicId, f.Slug, f.Title, f.Summary, f.SponsorName,
        f.FundingTypeId, f.Currency, f.MinAmount, f.MaxAmount,
        f.OpenDate, f.CloseDate, f.CloseAtUtc, f.DeadlineTimeZoneId,
        f.DeadlineType, f.DeadlinePrecision, f.GeographicScope,
        f.PublishedAtUtc, f.DataQualityScore
    FROM dbo.FundingPlatform_FundingOpportunities AS f
    WHERE f.PublicationStatus = 2
      AND f.IsActive = 1
      AND (@QueryLike IS NULL
           OR f.Title LIKE @QueryLike
           OR f.SponsorName LIKE @QueryLike
           OR f.Summary LIKE @QueryLike)
      AND (@FundingTypeId IS NULL OR f.FundingTypeId = @FundingTypeId)
      AND (@FundingCategoryId IS NULL OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCategories AS fc
           WHERE fc.FundingOpportunityId = f.Id AND fc.FundingCategoryId = @FundingCategoryId))
      AND (@CountryId IS NULL OR f.GeographicScope = 2 OR EXISTS
          (SELECT 1 FROM dbo.FundingPlatform_FundingOpportunityCountries AS fco
           WHERE fco.FundingOpportunityId = f.Id AND fco.CountryId = @CountryId))
      AND (@OnlyOpen = 0
           OR f.DeadlineType = 0
           OR f.DeadlineType = 2
           OR (f.DeadlineType = 1 AND f.DeadlinePrecision = 1 AND f.CloseDate >= CONVERT(DATE, @NowUtc))
           OR (f.DeadlineType = 1 AND f.DeadlinePrecision = 2 AND f.CloseAtUtc >= @NowUtc))
    ORDER BY CASE WHEN f.CloseDate IS NULL THEN 1 ELSE 0 END, f.CloseDate, f.Id DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END;';

/* Outbox lease procedures. Queue delivery remains at-least-once by design. */
EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Outbox_Claim
    @LeaseOwner NVARCHAR(100),
    @BatchSize INT,
    @LeaseSeconds INT,
    @NowUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NULLIF(LTRIM(RTRIM(@LeaseOwner)), N'''') IS NULL
        THROW 51030, N''LeaseOwner is required.'', 1;
    IF @BatchSize < 1 OR @BatchSize > 100
        THROW 51031, N''BatchSize must be between 1 and 100.'', 1;
    IF @LeaseSeconds < 5 OR @LeaseSeconds > 3600
        THROW 51032, N''LeaseSeconds must be between 5 and 3600.'', 1;

    ;WITH Claimable AS
    (
        SELECT TOP (@BatchSize) *
        FROM dbo.FundingPlatform_OutboxMessages WITH (UPDLOCK, READPAST, READCOMMITTEDLOCK)
        WHERE DispatchedAtUtc IS NULL
          AND AvailableAtUtc <= @NowUtc
          AND (LeaseUntilUtc IS NULL OR LeaseUntilUtc <= @NowUtc)
        ORDER BY AvailableAtUtc, Id
    )
    UPDATE Claimable
    SET LeaseOwner = @LeaseOwner,
        LeaseUntilUtc = DATEADD(SECOND, @LeaseSeconds, @NowUtc),
        AttemptCount = AttemptCount + 1
    OUTPUT
        inserted.Id, inserted.MessageId, inserted.MessageType,
        inserted.AggregateType, inserted.AggregateId, inserted.PayloadJson,
        inserted.OccurredAtUtc, inserted.AttemptCount, inserted.LeaseUntilUtc;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Outbox_Complete
    @MessageId UNIQUEIDENTIFIER,
    @LeaseOwner NVARCHAR(100),
    @DispatchedAtUtc DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FundingPlatform_OutboxMessages
    SET DispatchedAtUtc = @DispatchedAtUtc,
        LeaseOwner = NULL,
        LeaseUntilUtc = NULL,
        LastError = NULL
    WHERE MessageId = @MessageId
      AND DispatchedAtUtc IS NULL
      AND LeaseOwner = @LeaseOwner;

    IF @@ROWCOUNT = 0
        THROW 51033, N''Outbox message is not held by this lease owner or was already dispatched.'', 1;
END;';

EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.FundingPlatform_usp_Outbox_Release
    @MessageId UNIQUEIDENTIFIER,
    @LeaseOwner NVARCHAR(100),
    @AvailableAtUtc DATETIME2(3),
    @ErrorCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.FundingPlatform_OutboxMessages
    SET AvailableAtUtc = @AvailableAtUtc,
        LeaseOwner = NULL,
        LeaseUntilUtc = NULL,
        LastError = @ErrorCode
    WHERE MessageId = @MessageId
      AND DispatchedAtUtc IS NULL
      AND LeaseOwner = @LeaseOwner;

    IF @@ROWCOUNT = 0
        THROW 51034, N''Outbox message is not held by this lease owner or was already dispatched.'', 1;
END;';
