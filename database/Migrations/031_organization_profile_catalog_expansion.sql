/* FundingPlatform - organization profile catalog expansion.
   Requires migrations 001-030.

   Compatibility rules:
   - historical catalog identifiers and codes are never deleted or re-keyed;
   - legacy organization-size rows remain active because published organizations
     can still reference them;
   - existing category/type codes keep their meaning and receive only the
     explicitly documented broader display labels requested for the profile;
   - new rows use deterministic identifiers and fail closed on collisions.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID(N'dbo.FundingPlatform_OrganizationSizes', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_FundingCategories', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_BeneficiaryTypes', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_ProjectTypes', N'U') IS NULL
   OR OBJECT_ID(N'dbo.FundingPlatform_Languages', N'U') IS NULL
    THROW 55101, N'Organization profile catalog expansion requires migration 001.', 1;

DECLARE @NowUtc DATETIME2(3) = SYSUTCDATETIME();

/* The old MICRO/SMALL/MEDIUM/LARGE bands cannot be mapped safely without a
   stored employee count. Keep them unchanged for existing references and add
   the four new choices under distinct stable codes. */
DECLARE @OrganizationSizes TABLE
(
    Id SMALLINT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    Name NVARCHAR(150) NOT NULL,
    MinEmployees INT NULL,
    MaxEmployees INT NULL
);

INSERT INTO @OrganizationSizes (Id, Code, Name, MinEmployees, MaxEmployees)
VALUES
    (CAST(5 AS SMALLINT), N'EMPLOYEES_1_10', N'1–10 personas', 1, 10),
    (CAST(6 AS SMALLINT), N'EMPLOYEES_11_50', N'11–50 personas', 11, 50),
    (CAST(7 AS SMALLINT), N'EMPLOYEES_51_100', N'51–100 personas', 51, 100),
    (CAST(8 AS SMALLINT), N'EMPLOYEES_101_PLUS', N'101+ personas', 101, NULL);

IF EXISTS
(
    SELECT 1
    FROM @OrganizationSizes AS Seed
    INNER JOIN dbo.FundingPlatform_OrganizationSizes AS Existing
        ON Existing.Id = Seed.Id OR Existing.Code = Seed.Code
    WHERE Existing.Id <> Seed.Id OR Existing.Code <> Seed.Code
)
    THROW 55102, N'Organization size catalog identifier or code collision.', 1;

INSERT INTO dbo.FundingPlatform_OrganizationSizes
    (Id, Code, Name, MinEmployees, MaxEmployees)
SELECT Seed.Id, Seed.Code, Seed.Name, Seed.MinEmployees, Seed.MaxEmployees
FROM @OrganizationSizes AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_OrganizationSizes AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @OrganizationSizes AS Seed
    LEFT JOIN dbo.FundingPlatform_OrganizationSizes AS Existing ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.Code <> Seed.Code
       OR Existing.Name <> Seed.Name
       OR ISNULL(Existing.MinEmployees, -1) <> ISNULL(Seed.MinEmployees, -1)
       OR ISNULL(Existing.MaxEmployees, -1) <> ISNULL(Seed.MaxEmployees, -1)
       OR Existing.IsActive <> 1
)
    THROW 55103, N'Organization size catalog expansion is inconsistent.', 1;

/* Stable category mappings whose requested wording is a compatible expansion:
   ENVIRONMENT, SOCIAL_DEVELOPMENT, HUMAN_RIGHTS, ECONOMIC_DEVELOPMENT and
   INNOVATION retain their historical identifiers and codes. */
DECLARE @CategoryLabels TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    PreviousName NVARCHAR(150) NOT NULL,
    RequestedName NVARCHAR(150) NOT NULL
);

INSERT INTO @CategoryLabels (Id, Code, PreviousName, RequestedName)
VALUES
    (1, N'ENVIRONMENT', N'Medio ambiente', N'Medio ambiente y biodiversidad'),
    (3, N'SOCIAL_DEVELOPMENT', N'Desarrollo social',
        N'Desarrollo social y reducción de la pobreza'),
    (6, N'HUMAN_RIGHTS', N'Derechos humanos',
        N'Derechos humanos, democracia y gobernanza'),
    (7, N'ECONOMIC_DEVELOPMENT', N'Desarrollo económico local',
        N'Desarrollo económico, empleo y emprendimiento'),
    (8, N'INNOVATION', N'Innovación y tecnología',
        N'Innovación, ciencia y tecnología');

IF EXISTS
(
    SELECT 1
    FROM @CategoryLabels AS Mapping
    LEFT JOIN dbo.FundingPlatform_FundingCategories AS Existing ON Existing.Id = Mapping.Id
    WHERE Existing.Id IS NULL
       OR Existing.Code <> Mapping.Code
       OR Existing.Name NOT IN (Mapping.PreviousName, Mapping.RequestedName)
       OR Existing.IsActive <> 1
)
    THROW 55104, N'A historical impact-area mapping has drifted.', 1;

UPDATE Existing
SET Name = Mapping.RequestedName,
    UpdatedAtUtc = @NowUtc
FROM dbo.FundingPlatform_FundingCategories AS Existing
INNER JOIN @CategoryLabels AS Mapping ON Mapping.Id = Existing.Id
WHERE Existing.Name = Mapping.PreviousName;

DECLARE @NewCategories TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    Name NVARCHAR(150) NOT NULL
);

INSERT INTO @NewCategories (Id, Code, Name)
VALUES
    (9, N'CLIMATE_CHANGE', N'Cambio climático'),
    (10, N'WATER_SANITATION', N'Agua y saneamiento'),
    (11, N'AGRICULTURE_FOOD_SECURITY', N'Agricultura y seguridad alimentaria'),
    (12, N'GENDER_EQUALITY', N'Género e igualdad'),
    (13, N'PEACE_CONFLICT_HUMANITARIAN', N'Paz, conflictos y ayuda humanitaria'),
    (14, N'CITIES_HOUSING_TERRITORIAL', N'Ciudades, vivienda y desarrollo territorial'),
    (15, N'SPORT_COMMUNITY_DEVELOPMENT', N'Deporte y desarrollo comunitario'),
    (16, N'OTHER', N'Otros');

IF EXISTS
(
    SELECT 1
    FROM @NewCategories AS Seed
    INNER JOIN dbo.FundingPlatform_FundingCategories AS Existing
        ON Existing.Id = Seed.Id OR Existing.Code = Seed.Code
    WHERE Existing.Id <> Seed.Id OR Existing.Code <> Seed.Code
)
    THROW 55105, N'Impact-area catalog identifier or code collision.', 1;

INSERT INTO dbo.FundingPlatform_FundingCategories (Id, ParentId, Code, Name)
SELECT Seed.Id, NULL, Seed.Code, Seed.Name
FROM @NewCategories AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_FundingCategories AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @NewCategories AS Seed
    LEFT JOIN dbo.FundingPlatform_FundingCategories AS Existing ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.ParentId IS NOT NULL
       OR Existing.Code <> Seed.Code
       OR Existing.Name <> Seed.Name
       OR Existing.IsActive <> 1
)
    THROW 55106, N'Impact-area catalog expansion is inconsistent.', 1;

DECLARE @BeneficiaryTypes TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    Name NVARCHAR(150) NOT NULL
);

INSERT INTO @BeneficiaryTypes (Id, Code, Name)
VALUES
    (9, N'RURAL_COMMUNITIES', N'Comunidades rurales'),
    (10, N'PEOPLE_IN_POVERTY_OR_VULNERABILITY',
        N'Personas en situación de pobreza o vulnerabilidad'),
    (11, N'ENTREPRENEURS_AND_SMALL_PRODUCERS',
        N'Emprendedores y pequeños productores'),
    (12, N'OTHER', N'Otros');

IF EXISTS
(
    SELECT 1
    FROM @BeneficiaryTypes AS Seed
    INNER JOIN dbo.FundingPlatform_BeneficiaryTypes AS Existing
        ON Existing.Id = Seed.Id OR Existing.Code = Seed.Code
    WHERE Existing.Id <> Seed.Id OR Existing.Code <> Seed.Code
)
    THROW 55107, N'Beneficiary catalog identifier or code collision.', 1;

INSERT INTO dbo.FundingPlatform_BeneficiaryTypes (Id, ParentId, Code, Name)
SELECT Seed.Id, NULL, Seed.Code, Seed.Name
FROM @BeneficiaryTypes AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_BeneficiaryTypes AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @BeneficiaryTypes AS Seed
    LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS Existing ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.ParentId IS NOT NULL
       OR Existing.Code <> Seed.Code
       OR Existing.Name <> Seed.Name
       OR Existing.IsActive <> 1
)
    THROW 55108, N'Beneficiary catalog expansion is inconsistent.', 1;

/* ADVOCACY and EMERGENCY_RESPONSE retain their stable identifiers. Their
   display names are widened to the requested project-type wording. PROGRAM is
   deliberately retained as an active legacy option for existing relations. */
DECLARE @ProjectTypeLabels TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    PreviousName NVARCHAR(150) NOT NULL,
    RequestedName NVARCHAR(150) NOT NULL
);

INSERT INTO @ProjectTypeLabels (Id, Code, PreviousName, RequestedName)
VALUES
    (5, N'ADVOCACY', N'Incidencia', N'Incidencia y políticas públicas'),
    (6, N'EMERGENCY_RESPONSE', N'Respuesta a emergencias',
        N'Ayuda humanitaria y respuesta a emergencias');

IF EXISTS
(
    SELECT 1
    FROM @ProjectTypeLabels AS Mapping
    LEFT JOIN dbo.FundingPlatform_ProjectTypes AS Existing ON Existing.Id = Mapping.Id
    WHERE Existing.Id IS NULL
       OR Existing.Code <> Mapping.Code
       OR Existing.Name NOT IN (Mapping.PreviousName, Mapping.RequestedName)
       OR Existing.IsActive <> 1
)
    THROW 55109, N'A historical project-type mapping has drifted.', 1;

UPDATE Existing
SET Name = Mapping.RequestedName,
    UpdatedAtUtc = @NowUtc
FROM dbo.FundingPlatform_ProjectTypes AS Existing
INNER JOIN @ProjectTypeLabels AS Mapping ON Mapping.Id = Existing.Id
WHERE Existing.Name = Mapping.PreviousName;

DECLARE @NewProjectTypes TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    Code NVARCHAR(50) NOT NULL UNIQUE,
    Name NVARCHAR(150) NOT NULL
);

INSERT INTO @NewProjectTypes (Id, Code, Name)
VALUES
    (7, N'COMMUNITY_DEVELOPMENT', N'Desarrollo comunitario'),
    (8, N'TRAINING_CAPACITY_DEVELOPMENT', N'Capacitación y desarrollo de capacidades'),
    (9, N'INNOVATION_TECHNOLOGY', N'Innovación y tecnología'),
    (10, N'ENTREPRENEURSHIP_PRODUCTIVE_DEVELOPMENT',
        N'Emprendimiento y desarrollo productivo'),
    (11, N'ENVIRONMENTAL_CONSERVATION_RESTORATION',
        N'Conservación y restauración ambiental'),
    (12, N'DISASTER_RISK_PREVENTION_REDUCTION',
        N'Prevención y reducción de riesgos de desastres'),
    (13, N'OTHER', N'Otros');

IF EXISTS
(
    SELECT 1
    FROM @NewProjectTypes AS Seed
    INNER JOIN dbo.FundingPlatform_ProjectTypes AS Existing
        ON Existing.Id = Seed.Id OR Existing.Code = Seed.Code
    WHERE Existing.Id <> Seed.Id OR Existing.Code <> Seed.Code
)
    THROW 55110, N'Project-type catalog identifier or code collision.', 1;

INSERT INTO dbo.FundingPlatform_ProjectTypes (Id, Code, Name)
SELECT Seed.Id, Seed.Code, Seed.Name
FROM @NewProjectTypes AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_ProjectTypes AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @NewProjectTypes AS Seed
    LEFT JOIN dbo.FundingPlatform_ProjectTypes AS Existing ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.Code <> Seed.Code
       OR Existing.Name <> Seed.Name
       OR Existing.IsActive <> 1
)
    THROW 55111, N'Project-type catalog expansion is inconsistent.', 1;

DECLARE @Languages TABLE
(
    Id SMALLINT NOT NULL PRIMARY KEY,
    IsoCode NVARCHAR(10) NOT NULL UNIQUE,
    Name NVARCHAR(120) NOT NULL
);

INSERT INTO @Languages (Id, IsoCode, Name)
VALUES
    (CAST(3 AS SMALLINT), N'pt', N'Portugués'),
    (CAST(4 AS SMALLINT), N'fr', N'Francés'),
    /* ISO 639-2 `und` represents an unspecified language behind “Otro”. */
    (CAST(5 AS SMALLINT), N'und', N'Otro');

IF EXISTS
(
    SELECT 1
    FROM @Languages AS Seed
    INNER JOIN dbo.FundingPlatform_Languages AS Existing
        ON Existing.Id = Seed.Id OR Existing.IsoCode = Seed.IsoCode
    WHERE Existing.Id <> Seed.Id OR Existing.IsoCode <> Seed.IsoCode
)
    THROW 55112, N'Language catalog identifier or ISO-code collision.', 1;

INSERT INTO dbo.FundingPlatform_Languages (Id, IsoCode, Name)
SELECT Seed.Id, Seed.IsoCode, Seed.Name
FROM @Languages AS Seed
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.FundingPlatform_Languages AS Existing
    WHERE Existing.Id = Seed.Id
);

IF EXISTS
(
    SELECT 1
    FROM @Languages AS Seed
    LEFT JOIN dbo.FundingPlatform_Languages AS Existing ON Existing.Id = Seed.Id
    WHERE Existing.Id IS NULL
       OR Existing.IsoCode <> Seed.IsoCode
       OR Existing.Name <> Seed.Name
       OR Existing.IsActive <> 1
)
    THROW 55113, N'Language catalog expansion is inconsistent.', 1;
