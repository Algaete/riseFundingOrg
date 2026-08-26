/* Read-only catalog smoke for the API, general worker and isolated extraction roles. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @ApiRoleId INT = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole');
DECLARE @GeneralWorkerRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole');
DECLARE @ExtractionWorkerRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_ExtractionWorkerRole');
DECLARE @SemanticWorkerRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticWorkerRole');
DECLARE @SemanticAdminRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_SemanticAdminRole');
DECLARE @AlertWorkerRoleId INT =
    DATABASE_PRINCIPAL_ID(N'FundingPlatform_AlertWorkerRole');

IF @ApiRoleId IS NULL OR @GeneralWorkerRoleId IS NULL
   OR @ExtractionWorkerRoleId IS NULL OR @SemanticWorkerRoleId IS NULL
   OR @SemanticAdminRoleId IS NULL OR @AlertWorkerRoleId IS NULL
    THROW 54850, N'Runtime or specialist database roles are incomplete.', 1;

IF EXISTS
   (
       SELECT 1
       FROM sys.database_principals AS roles
       WHERE roles.principal_id IN
             (@ApiRoleId, @GeneralWorkerRoleId, @ExtractionWorkerRoleId,
              @SemanticWorkerRoleId, @SemanticAdminRoleId, @AlertWorkerRoleId)
         AND (roles.type <> N'R'
              OR roles.owning_principal_id <> DATABASE_PRINCIPAL_ID(N'dbo'))
   )
    THROW 54851, N'Runtime and specialist principals must be dbo-owned roles.', 1;

/* The host roles have direct, object-scoped grants only. No role inheritance can
   silently add db_owner, db_datareader, db_datawriter or schema-wide access. */
IF EXISTS
   (
       SELECT 1
       FROM sys.database_role_members AS memberships
       WHERE memberships.member_principal_id IN (@ApiRoleId, @GeneralWorkerRoleId)
   )
    THROW 54852, N'A runtime role inherits another database role.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions AS permissions
    INNER JOIN sys.procedures AS procedures
        ON procedures.object_id = permissions.major_id
    WHERE permissions.grantee_principal_id = @ApiRoleId
      AND permissions.class = 1
      AND permissions.minor_id = 0
      AND permissions.permission_name = N'EXECUTE'
      AND permissions.state IN (N'G', N'W')) <> 116
    THROW 54853, N'The API stored-procedure allowlist count is invalid.', 1;

IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions AS permissions
    INNER JOIN sys.procedures AS procedures
        ON procedures.object_id = permissions.major_id
    WHERE permissions.grantee_principal_id = @GeneralWorkerRoleId
      AND permissions.class = 1
      AND permissions.minor_id = 0
      AND permissions.permission_name = N'EXECUTE'
      AND permissions.state IN (N'G', N'W')) <> 49
    THROW 54854, N'The general-worker stored-procedure allowlist count is invalid.', 1;

DECLARE @ApiProcedureMaterial NVARCHAR(MAX) =
   (
       SELECT STRING_AGG(
                  CONVERT(NVARCHAR(MAX),
                          SCHEMA_NAME(procedures.schema_id) + N'.' + procedures.name),
                  NCHAR(10))
              WITHIN GROUP
              (ORDER BY (SCHEMA_NAME(procedures.schema_id) + N'.' + procedures.name)
                        COLLATE Latin1_General_100_BIN2)
       FROM sys.database_permissions AS permissions
       INNER JOIN sys.procedures AS procedures
           ON procedures.object_id = permissions.major_id
       WHERE permissions.grantee_principal_id = @ApiRoleId
         AND permissions.class = 1
         AND permissions.minor_id = 0
         AND permissions.permission_name = N'EXECUTE'
         AND permissions.state IN (N'G', N'W')
   );
DECLARE @GeneralWorkerProcedureMaterial NVARCHAR(MAX) =
   (
       SELECT STRING_AGG(
                  CONVERT(NVARCHAR(MAX),
                          SCHEMA_NAME(procedures.schema_id) + N'.' + procedures.name),
                  NCHAR(10))
              WITHIN GROUP
              (ORDER BY (SCHEMA_NAME(procedures.schema_id) + N'.' + procedures.name)
                        COLLATE Latin1_General_100_BIN2)
       FROM sys.database_permissions AS permissions
       INNER JOIN sys.procedures AS procedures
           ON procedures.object_id = permissions.major_id
       WHERE permissions.grantee_principal_id = @GeneralWorkerRoleId
         AND permissions.class = 1
         AND permissions.minor_id = 0
         AND permissions.permission_name = N'EXECUTE'
         AND permissions.state IN (N'G', N'W')
   );

IF HASHBYTES(N'SHA2_256', @ApiProcedureMaterial) <>
       0x4448EADD744D003B0CAF35BAB3A1BFA635BEF7B2AD46A09E485F1B1EA2AC9505
   OR HASHBYTES(N'SHA2_256', @GeneralWorkerProcedureMaterial) <>
       0x0D65C72A3143DABC51A183F11C62C58180F0C954514B0734125B5D34874D8A9D
    THROW 54855, N'The runtime stored-procedure allowlist fingerprint is invalid.', 1;

DECLARE @ExpectedApiTablePermissions TABLE
(
    ObjectId INT NOT NULL,
    PermissionName NVARCHAR(60) NOT NULL,
    PRIMARY KEY (ObjectId, PermissionName)
);
INSERT INTO @ExpectedApiTablePermissions (ObjectId, PermissionName)
SELECT OBJECT_ID(required.ObjectName, N'U'), required.PermissionName
FROM (VALUES
    (N'dbo.FundingPlatform_Users', N'SELECT'),
    (N'dbo.FundingPlatform_Users', N'INSERT'),
    (N'dbo.FundingPlatform_Users', N'UPDATE'),
    (N'dbo.FundingPlatform_UserAuthenticatorKeys', N'SELECT'),
    (N'dbo.FundingPlatform_UserAuthenticatorKeys', N'INSERT'),
    (N'dbo.FundingPlatform_UserAuthenticatorKeys', N'UPDATE'),
    (N'dbo.FundingPlatform_UserRoles', N'SELECT'),
    (N'dbo.FundingPlatform_UserRoles', N'INSERT'),
    (N'dbo.FundingPlatform_UserRoles', N'DELETE'),
    (N'dbo.FundingPlatform_Roles', N'SELECT'),
    (N'dbo.FundingPlatform_UserMfaChallenges', N'SELECT'),
    (N'dbo.FundingPlatform_UserMfaChallenges', N'INSERT'),
    (N'dbo.FundingPlatform_UserMfaChallenges', N'UPDATE'),
    (N'dbo.FundingPlatform_UserRecoveryCodes', N'SELECT'),
    (N'dbo.FundingPlatform_UserRecoveryCodes', N'INSERT'),
    (N'dbo.FundingPlatform_UserRecoveryCodes', N'UPDATE'),
    (N'dbo.FundingPlatform_UserRecoveryCodes', N'DELETE'),
    (N'dbo.FundingPlatform_AuthenticationEvents', N'INSERT')
) AS required(ObjectName, PermissionName);

IF (SELECT COUNT_BIG(1) FROM @ExpectedApiTablePermissions) <> 18
   OR EXISTS (SELECT 1 FROM @ExpectedApiTablePermissions WHERE ObjectId IS NULL)
   OR EXISTS
      (
          SELECT expected.ObjectId, expected.PermissionName
          FROM @ExpectedApiTablePermissions AS expected
          EXCEPT
          SELECT permissions.major_id, permissions.permission_name
          FROM sys.database_permissions AS permissions
          WHERE permissions.grantee_principal_id = @ApiRoleId
            AND permissions.class = 1
            AND permissions.minor_id = 0
            AND permissions.state IN (N'G', N'W')
      )
   OR EXISTS
      (
          SELECT permissions.major_id, permissions.permission_name
          FROM sys.database_permissions AS permissions
          INNER JOIN sys.tables AS tables
              ON tables.object_id = permissions.major_id
          WHERE permissions.grantee_principal_id = @ApiRoleId
            AND permissions.class = 1
            AND permissions.minor_id = 0
            AND permissions.state IN (N'G', N'W')
          EXCEPT
          SELECT expected.ObjectId, expected.PermissionName
          FROM @ExpectedApiTablePermissions AS expected
      )
    THROW 54856, N'The API direct-table permission contract is invalid.', 1;

DECLARE @ExpectedApiTypePermissions TABLE
(
    TypeId INT NOT NULL,
    PermissionName NVARCHAR(60) NOT NULL,
    PRIMARY KEY (TypeId, PermissionName)
);
INSERT INTO @ExpectedApiTypePermissions (TypeId, PermissionName)
SELECT TYPE_ID(required.TypeName), permissions.PermissionName
FROM (VALUES
    (N'dbo.FundingPlatform_SmallIntIdList'),
    (N'dbo.FundingPlatform_IntIdList'),
    (N'dbo.FundingPlatform_BigIntIdList'),
    (N'dbo.FundingPlatform_GuidIdList'),
    (N'dbo.FundingPlatform_OrganizationLanguageList')
) AS required(TypeName)
CROSS JOIN (VALUES (N'EXECUTE'), (N'REFERENCES')) AS permissions(PermissionName);

IF (SELECT COUNT_BIG(1) FROM @ExpectedApiTypePermissions) <> 10
   OR EXISTS (SELECT 1 FROM @ExpectedApiTypePermissions WHERE TypeId IS NULL)
   OR EXISTS
      (
          SELECT expected.TypeId, expected.PermissionName
          FROM @ExpectedApiTypePermissions AS expected
          EXCEPT
          SELECT permissions.major_id, permissions.permission_name
          FROM sys.database_permissions AS permissions
          WHERE permissions.grantee_principal_id = @ApiRoleId
            AND permissions.class = 6
            AND permissions.state IN (N'G', N'W')
      )
   OR EXISTS
      (
          SELECT permissions.major_id, permissions.permission_name
          FROM sys.database_permissions AS permissions
          WHERE permissions.grantee_principal_id = @ApiRoleId
            AND permissions.class = 6
            AND permissions.state IN (N'G', N'W')
          EXCEPT
          SELECT expected.TypeId, expected.PermissionName
          FROM @ExpectedApiTypePermissions AS expected
      )
    THROW 54857, N'The API table-type permission contract is invalid.', 1;

/* Any extra class, DENY, schema/database grant, worker DML or non-EXECUTE
   procedure permission is outside the frozen runtime contract. */
IF EXISTS
   (
       SELECT 1
       FROM sys.database_permissions AS permissions
       LEFT JOIN sys.procedures AS procedures
           ON permissions.class = 1 AND procedures.object_id = permissions.major_id
       LEFT JOIN sys.tables AS tables
           ON permissions.class = 1 AND tables.object_id = permissions.major_id
       WHERE permissions.grantee_principal_id = @ApiRoleId
         AND NOT
             (
                 permissions.state IN (N'G', N'W')
                 AND
                 (
                     (procedures.object_id IS NOT NULL
                      AND permissions.minor_id = 0
                      AND permissions.permission_name = N'EXECUTE')
                     OR (tables.object_id IS NOT NULL
                         AND permissions.minor_id = 0 AND EXISTS
                         (SELECT 1 FROM @ExpectedApiTablePermissions AS expected
                          WHERE expected.ObjectId = permissions.major_id
                            AND expected.PermissionName = permissions.permission_name))
                     OR (permissions.class = 6 AND EXISTS
                         (SELECT 1 FROM @ExpectedApiTypePermissions AS expected
                          WHERE expected.TypeId = permissions.major_id
                            AND expected.PermissionName = permissions.permission_name))
                 )
             )
   )
   OR EXISTS
      (
          SELECT 1
          FROM sys.database_permissions AS permissions
          WHERE permissions.grantee_principal_id = @GeneralWorkerRoleId
            AND NOT
                (permissions.class = 1
                 AND permissions.minor_id = 0
                 AND permissions.permission_name = N'EXECUTE'
                 AND permissions.state IN (N'G', N'W')
                 AND EXISTS (SELECT 1 FROM sys.procedures AS procedures
                             WHERE procedures.object_id = permissions.major_id))
      )
    THROW 54858, N'A runtime role has permission outside its bounded contract.', 1;

IF (SELECT COUNT_BIG(1) FROM sys.database_permissions
    WHERE grantee_principal_id = @ApiRoleId) <> 144
   OR (SELECT COUNT_BIG(1) FROM sys.database_permissions
       WHERE grantee_principal_id = @GeneralWorkerRoleId) <> 49
    THROW 54859, N'Runtime roles contain an unexpected direct permission.', 1;

IF EXISTS
   (
       SELECT 1
       FROM sys.database_permissions AS permissions
       WHERE (permissions.grantee_principal_id = @ApiRoleId
              AND permissions.major_id IN
                  (OBJECT_ID(N'dbo.FundingPlatform_usp_ImportRun_Claim'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_AlertSchedule_Claim'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim')))
          OR (permissions.grantee_principal_id = @GeneralWorkerRoleId
              AND permissions.major_id IN
                  (OBJECT_ID(N'dbo.FundingPlatform_usp_User_Register'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_SemanticEvaluationRun_Create'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_AiExplanationRun_Create'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_SavedSearch_Create'),
                   OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim')))
   )
    THROW 54860, N'API, general-worker or extraction boundaries overlap.', 1;

/* 016 remains the only grant source for the isolated extraction host. */
IF (SELECT COUNT_BIG(1)
    FROM sys.database_permissions AS permissions
    INNER JOIN sys.procedures AS procedures
        ON procedures.object_id = permissions.major_id
    WHERE permissions.grantee_principal_id = @ExtractionWorkerRoleId
      AND permissions.class = 1
      AND permissions.minor_id = 0
      AND permissions.permission_name = N'EXECUTE'
      AND permissions.state IN (N'G', N'W')) <> 6
   OR EXISTS
      (
          SELECT 1
          FROM sys.database_permissions AS permissions
          WHERE permissions.grantee_principal_id = @ExtractionWorkerRoleId
            AND NOT
                (permissions.class = 1
                 AND permissions.minor_id = 0
                 AND permissions.permission_name = N'EXECUTE'
                 AND permissions.state IN (N'G', N'W')
                 AND permissions.major_id IN
                     (OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim'),
                      OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RenewLease'),
                      OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RecordEvidence'),
                      OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Complete'),
                      OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_Fail'),
                      OBJECT_ID(N'dbo.FundingPlatform_usp_SourceDocumentExtraction_RequeueStranded')))
      )
    THROW 54861, N'The isolated extraction role changed outside its six-procedure contract.', 1;

DECLARE @OrganizationSearchObjectId INT =
    OBJECT_ID(N'dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch', N'P');
IF NOT EXISTS
   (
       SELECT 1
       FROM sys.sql_modules AS modules
       WHERE modules.object_id = @OrganizationSearchObjectId
         AND modules.execute_as_principal_id = -2
         AND modules.definition LIKE N'%sys.sp_executesql%'
         AND modules.definition LIKE N'%FREETEXTTABLE%'
   )
    THROW 54862, N'Organization search lost its OWNER execution context.', 1;

/* Prove effective permissions with randomized users that exist only inside this
   transaction. No deployment identity or database membership survives. */
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke027;

BEGIN TRY
    DECLARE @Suffix NVARCHAR(32) =
        REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'');
    DECLARE @ApiTestUser SYSNAME = N'fp_api_runtime_' + @Suffix;
    DECLARE @WorkerTestUser SYSNAME = N'fp_general_worker_' + @Suffix;
    DECLARE @ExtractionTestUser SYSNAME = N'fp_extraction_' + @Suffix;
    DECLARE @PermissionSql NVARCHAR(MAX) =
        N'CREATE USER ' + QUOTENAME(@ApiTestUser) + N' WITHOUT LOGIN;'
        + N'ALTER ROLE FundingPlatform_ApiRuntimeRole ADD MEMBER '
        + QUOTENAME(@ApiTestUser) + N';'
        + N'CREATE USER ' + QUOTENAME(@WorkerTestUser) + N' WITHOUT LOGIN;'
        + N'ALTER ROLE FundingPlatform_GeneralWorkerRole ADD MEMBER '
        + QUOTENAME(@WorkerTestUser) + N';'
        + N'CREATE USER ' + QUOTENAME(@ExtractionTestUser) + N' WITHOUT LOGIN;'
        + N'ALTER ROLE FundingPlatform_ExtractionWorkerRole ADD MEMBER '
        + QUOTENAME(@ExtractionTestUser) + N';';
    EXEC sys.sp_executesql @PermissionSql;

    SET @PermissionSql = N'
EXECUTE AS USER = N''' + REPLACE(@ApiTestUser, N'''', N'''''') + N''';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(
           N''dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch'',
           N''OBJECT'', N''EXECUTE'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_Users'', N''OBJECT'', N''SELECT'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_Users'', N''OBJECT'', N''UPDATE'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SmallIntIdList'',
                            N''TYPE'', N''EXECUTE'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SmallIntIdList'',
                            N''TYPE'', N''REFERENCES'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_OrganizationLanguageList'',
                            N''TYPE'', N''EXECUTE'') <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(
              N''dbo.FundingPlatform_usp_ImportRun_Claim'',
              N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(
              N''dbo.FundingPlatform_FundingOpportunities'',
              N''OBJECT'', N''SELECT''), 0) <> 0
        THROW 54863, N''API effective permissions are invalid.'', 1;

    DECLARE @CountryIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @RegionIds dbo.FundingPlatform_IntIdList;
    DECLARE @CategoryIds dbo.FundingPlatform_IntIdList;
    DECLARE @TagIds dbo.FundingPlatform_BigIntIdList;
    DECLARE @BeneficiaryTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @ProjectTypeIds dbo.FundingPlatform_IntIdList;
    DECLARE @FundingTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @FunderPublicIds dbo.FundingPlatform_GuidIdList;
    DECLARE @OrganizationTypeIds dbo.FundingPlatform_SmallIntIdList;
    DECLARE @Languages dbo.FundingPlatform_OrganizationLanguageList;
    DECLARE @MatchedCount BIGINT, @SearchMode NVARCHAR(20);
    BEGIN TRY
        EXEC dbo.FundingPlatform_usp_FundingOpportunity_OrganizationSearch
            @UserPublicId = ''00000000-0000-0000-0000-000000000001'',
            @OrganizationPublicId = ''00000000-0000-0000-0000-000000000002'',
            @Query = N''permission-smoke'', @CountryIds = @CountryIds,
            @RegionIds = @RegionIds, @CategoryIds = @CategoryIds,
            @TagIds = @TagIds, @BeneficiaryTypeIds = @BeneficiaryTypeIds,
            @ProjectTypeIds = @ProjectTypeIds, @FundingTypeIds = @FundingTypeIds,
            @FunderPublicIds = @FunderPublicIds,
            @OrganizationTypeIds = @OrganizationTypeIds,
            @MatchedCount = @MatchedCount OUTPUT,
            @EffectiveSearchMode = @SearchMode OUTPUT;
        THROW 54864, N''Organization search accepted an unknown tenant.'', 1;
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() <> 52001 THROW;
    END CATCH;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;';
    EXEC sys.sp_executesql @PermissionSql;

    SET @PermissionSql = N'
EXECUTE AS USER = N''' + REPLACE(@WorkerTestUser, N'''', N'''''') + N''';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_ImportRun_Claim'',
                         N''OBJECT'', N''EXECUTE'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SemanticEmbeddingJob_Claim'',
                            N''OBJECT'', N''EXECUTE'') <> 1
       OR HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_AlertSchedule_Claim'',
                            N''OBJECT'', N''EXECUTE'') <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_User_Register'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_FundingOpportunities'',
                                     N''OBJECT'', N''SELECT''), 0) <> 0
        THROW 54865, N''General-worker effective permissions are invalid.'', 1;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;';
    EXEC sys.sp_executesql @PermissionSql;

    SET @PermissionSql = N'
EXECUTE AS USER = N''' + REPLACE(@ExtractionTestUser, N'''', N'''''') + N''';
BEGIN TRY
    IF HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim'',
                         N''OBJECT'', N''EXECUTE'') <> 1
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_usp_ImportRun_Claim'',
                                     N''OBJECT'', N''EXECUTE''), 0) <> 0
       OR COALESCE(HAS_PERMS_BY_NAME(N''dbo.FundingPlatform_SourceDocuments'',
                                     N''OBJECT'', N''SELECT''), 0) <> 0
        THROW 54866, N''Extraction effective permissions are invalid.'', 1;
    REVERT;
END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;';
    EXEC sys.sp_executesql @PermissionSql;

    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke027;
    PRINT N'Runtime database roles smoke passed.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
    BEGIN
        IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke027;
        ELSE ROLLBACK TRANSACTION;
    END;
    THROW;
END CATCH;
