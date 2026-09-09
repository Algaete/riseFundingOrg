/* Transactional smoke for migration 031. The outer migrator owns the connection. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke031;

BEGIN TRY
    DECLARE @ExpectedOrganizationSizes TABLE
    (
        Id SMALLINT NOT NULL PRIMARY KEY,
        Code NVARCHAR(50) NOT NULL,
        Name NVARCHAR(150) NOT NULL,
        MinEmployees INT NULL,
        MaxEmployees INT NULL
    );
    INSERT INTO @ExpectedOrganizationSizes (Id, Code, Name, MinEmployees, MaxEmployees)
    VALUES
        (5, N'EMPLOYEES_1_10', N'1–10 personas', 1, 10),
        (6, N'EMPLOYEES_11_50', N'11–50 personas', 11, 50),
        (7, N'EMPLOYEES_51_100', N'51–100 personas', 51, 100),
        (8, N'EMPLOYEES_101_PLUS', N'101+ personas', 101, NULL);

    IF EXISTS
    (
        SELECT 1
        FROM @ExpectedOrganizationSizes AS Expected
        LEFT JOIN dbo.FundingPlatform_OrganizationSizes AS Actual ON Actual.Id = Expected.Id
        WHERE Actual.Id IS NULL
           OR Actual.Code <> Expected.Code
           OR Actual.Name <> Expected.Name
           OR ISNULL(Actual.MinEmployees, -1) <> ISNULL(Expected.MinEmployees, -1)
           OR ISNULL(Actual.MaxEmployees, -1) <> ISNULL(Expected.MaxEmployees, -1)
           OR Actual.IsActive <> 1
    )
        THROW 55120, N'Organization size expansion smoke failed.', 1;

    /* Historical rows remain addressable and active so existing organization
       profiles do not become ineligible for publication. */
    IF NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationSizes
        WHERE Id = 1 AND Code = N'MICRO' AND Name = N'Micro'
          AND MinEmployees = 0 AND MaxEmployees = 9 AND IsActive = 1)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationSizes
        WHERE Id = 2 AND Code = N'SMALL' AND Name = N'Pequeña'
          AND MinEmployees = 10 AND MaxEmployees = 49 AND IsActive = 1)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationSizes
        WHERE Id = 3 AND Code = N'MEDIUM' AND Name = N'Mediana'
          AND MinEmployees = 50 AND MaxEmployees = 199 AND IsActive = 1)
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_OrganizationSizes
        WHERE Id = 4 AND Code = N'LARGE' AND Name = N'Grande'
          AND MinEmployees = 200 AND MaxEmployees IS NULL AND IsActive = 1)
        THROW 55121, N'Historical organization size rows were not preserved.', 1;

    DECLARE @ExpectedCategories TABLE
    (
        Id INT NOT NULL PRIMARY KEY,
        Code NVARCHAR(50) NOT NULL,
        Name NVARCHAR(150) NOT NULL
    );
    INSERT INTO @ExpectedCategories (Id, Code, Name)
    VALUES
        (1, N'ENVIRONMENT', N'Medio ambiente y biodiversidad'),
        (2, N'EDUCATION', N'Educación'),
        (3, N'SOCIAL_DEVELOPMENT', N'Desarrollo social y reducción de la pobreza'),
        (4, N'HEALTH', N'Salud'),
        (5, N'CULTURE', N'Cultura y patrimonio'),
        (6, N'HUMAN_RIGHTS', N'Derechos humanos, democracia y gobernanza'),
        (7, N'ECONOMIC_DEVELOPMENT', N'Desarrollo económico, empleo y emprendimiento'),
        (8, N'INNOVATION', N'Innovación, ciencia y tecnología'),
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
        FROM @ExpectedCategories AS Expected
        LEFT JOIN dbo.FundingPlatform_FundingCategories AS Actual ON Actual.Id = Expected.Id
        WHERE Actual.Id IS NULL
           OR Actual.Code <> Expected.Code
           OR Actual.Name <> Expected.Name
           OR Actual.IsActive <> 1
    )
        THROW 55122, N'Impact-area expansion smoke failed.', 1;

    DECLARE @ExpectedBeneficiaries TABLE
    (
        Id INT NOT NULL PRIMARY KEY,
        Code NVARCHAR(50) NOT NULL,
        Name NVARCHAR(150) NOT NULL
    );
    INSERT INTO @ExpectedBeneficiaries (Id, Code, Name)
    VALUES
        (1, N'CHILDREN', N'Niños, niñas y adolescentes'),
        (2, N'YOUTH', N'Jóvenes'),
        (3, N'OLDER_ADULTS', N'Personas mayores'),
        (4, N'WOMEN', N'Mujeres'),
        (5, N'PEOPLE_WITH_DISABILITIES', N'Personas con discapacidad'),
        (6, N'INDIGENOUS_PEOPLES', N'Pueblos indígenas'),
        (7, N'MIGRANTS', N'Personas migrantes y refugiadas'),
        (8, N'COMMUNITIES', N'Comunidades y organizaciones territoriales'),
        (9, N'RURAL_COMMUNITIES', N'Comunidades rurales'),
        (10, N'PEOPLE_IN_POVERTY_OR_VULNERABILITY',
            N'Personas en situación de pobreza o vulnerabilidad'),
        (11, N'ENTREPRENEURS_AND_SMALL_PRODUCERS',
            N'Emprendedores y pequeños productores'),
        (12, N'OTHER', N'Otros');

    IF EXISTS
    (
        SELECT 1
        FROM @ExpectedBeneficiaries AS Expected
        LEFT JOIN dbo.FundingPlatform_BeneficiaryTypes AS Actual ON Actual.Id = Expected.Id
        WHERE Actual.Id IS NULL
           OR Actual.Code <> Expected.Code
           OR Actual.Name <> Expected.Name
           OR Actual.IsActive <> 1
    )
        THROW 55123, N'Beneficiary expansion smoke failed.', 1;

    DECLARE @ExpectedProjectTypes TABLE
    (
        Id INT NOT NULL PRIMARY KEY,
        Code NVARCHAR(50) NOT NULL,
        Name NVARCHAR(150) NOT NULL
    );
    INSERT INTO @ExpectedProjectTypes (Id, Code, Name)
    VALUES
        (2, N'RESEARCH', N'Investigación'),
        (3, N'INFRASTRUCTURE', N'Infraestructura'),
        (4, N'CAPACITY_BUILDING', N'Fortalecimiento institucional'),
        (5, N'ADVOCACY', N'Incidencia y políticas públicas'),
        (6, N'EMERGENCY_RESPONSE', N'Ayuda humanitaria y respuesta a emergencias'),
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
        FROM @ExpectedProjectTypes AS Expected
        LEFT JOIN dbo.FundingPlatform_ProjectTypes AS Actual ON Actual.Id = Expected.Id
        WHERE Actual.Id IS NULL
           OR Actual.Code <> Expected.Code
           OR Actual.Name <> Expected.Name
           OR Actual.IsActive <> 1
    )
       OR NOT EXISTS
       (SELECT 1 FROM dbo.FundingPlatform_ProjectTypes
        WHERE Id = 1 AND Code = N'PROGRAM' AND Name = N'Programa' AND IsActive = 1)
        THROW 55124, N'Project-type expansion or legacy preservation smoke failed.', 1;

    DECLARE @ExpectedLanguages TABLE
    (
        Id SMALLINT NOT NULL PRIMARY KEY,
        IsoCode NVARCHAR(10) NOT NULL,
        Name NVARCHAR(120) NOT NULL
    );
    INSERT INTO @ExpectedLanguages (Id, IsoCode, Name)
    VALUES
        (1, N'es', N'Español'),
        (2, N'en', N'Inglés'),
        (3, N'pt', N'Portugués'),
        (4, N'fr', N'Francés'),
        (5, N'und', N'Otro');

    IF EXISTS
    (
        SELECT 1
        FROM @ExpectedLanguages AS Expected
        LEFT JOIN dbo.FundingPlatform_Languages AS Actual ON Actual.Id = Expected.Id
        WHERE Actual.Id IS NULL
           OR Actual.IsoCode <> Expected.IsoCode
           OR Actual.Name <> Expected.Name
           OR Actual.IsActive <> 1
    )
        THROW 55125, N'Language expansion smoke failed.', 1;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke031;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1
        ROLLBACK TRANSACTION FP_Smoke031;
    THROW;
END CATCH;
