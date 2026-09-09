/* Transactional smoke: no Blob calls; all fixture data and simulated receipts roll back. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @InitialTransactionCount INT = @@TRANCOUNT;
IF @InitialTransactionCount = 0 BEGIN TRANSACTION;
ELSE SAVE TRANSACTION FP_Smoke039;
BEGIN TRY
    DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @Old DATETIME2(3) = '2000-01-01';
    DECLARE @User UNIQUEIDENTIFIER = NEWID(), @Suffix NVARCHAR(32) = LOWER(REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N''));
    DECLARE @Email NVARCHAR(320) = N'retention-' + @Suffix + N'@example.invalid';
    INSERT dbo.FundingPlatform_Users
        (PublicId, Email, NormalizedEmail, DisplayName, PasswordHash, SecurityStamp,
         EmailConfirmed, TwoFactorEnabled, Status, PreferredLocale)
    VALUES (@User, @Email, UPPER(@Email), N'Retention smoke', N'not-a-credential',
            N'retention-smoke', 1, 1, 2, N'es-CL');
    DECLARE @UserId BIGINT = (SELECT Id FROM dbo.FundingPlatform_Users WHERE PublicId = @User);
    DECLARE @Org TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProfileVersion INT, RowVersion BINARY(8));
    DECLARE @Hash BINARY(32) = HASHBYTES('SHA2_256', N'retention-smoke');
    INSERT @Org EXEC dbo.FundingPlatform_usp_Organization_CreateForUser
        @UserPublicId = @User, @Name = N'Retention smoke', @HomeCountryId = 152,
        @OrganizationTypeId = 2, @SnapshotJson = N'{"name":"Retention smoke"}', @ContentHash = @Hash;
    DECLARE @OrgPublic UNIQUEIDENTIFIER = (SELECT PublicId FROM @Org);
    DECLARE @Countries dbo.FundingPlatform_SmallIntIdList;
    DECLARE @Regions dbo.FundingPlatform_IntIdList, @Categories dbo.FundingPlatform_IntIdList;
    DECLARE @Beneficiaries dbo.FundingPlatform_IntIdList, @Types dbo.FundingPlatform_IntIdList;
    INSERT @Countries VALUES (152);
    INSERT @Regions VALUES (7);
    INSERT @Categories VALUES (1);
    INSERT @Beneficiaries VALUES (1);
    INSERT @Types VALUES (1);
    DECLARE @Project TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, ProjectVersion INT, RowVersion BINARY(8));
    DECLARE @Slug NVARCHAR(180) = N'retention-' + @Suffix;
    INSERT @Project EXEC dbo.FundingPlatform_usp_Project_Create
        @OrganizationPublicId = @OrgPublic, @UserPublicId = @User, @Slug = @Slug,
        @Title = N'Retention smoke', @Summary = N'Retención de adjuntos.',
        @Description = N'Validación transaccional de retención de adjuntos.',
        @ProjectStatus = 2, @StartDate = '2027-01-01', @EndDate = '2027-12-31',
        @BudgetTotal = 100000, @ConfirmedFunding = 10000, @Currency = 'CLP',
        @SnapshotJson = N'{"title":"Retention smoke","projectStage":1,"sustainableDevelopmentGoalIds":[1]}',
        @ContentHash = @Hash, @CountryIds = @Countries, @RegionIds = @Regions,
        @CategoryIds = @Categories, @BeneficiaryTypeIds = @Beneficiaries, @ProjectTypeIds = @Types,
        @ProjectStage = 1, @ProjectStageIsSpecified = 1, @SustainableDevelopmentGoalIdsJson = N'[1]';
    DECLARE @ProjectId BIGINT = (SELECT Id FROM @Project);
    DECLARE @Assets TABLE (Id BIGINT, PublicId UNIQUEIDENTIFIER, Fixture INT);
    /* 1 active clean; 2 deleted clean; 3 malicious; 4 failed; 5 timed out;
       6 recent deleted; 7 legacy revoked image; 8 sanitized revoked image. */
    INSERT dbo.FundingPlatform_ProjectAssets
        (PublicId, ProjectId, Kind, OriginalFileName, VerifiedMimeType, ContentLength, ContentHash,
         PixelWidth, PixelHeight,
         QuarantineBlobContainer, QuarantineBlobObjectName, QuarantineBlobETag, QuarantineBlobVersionId,
         TrustedBlobContainer, TrustedBlobObjectName, TrustedBlobETag, TrustedBlobVersionId,
         TrustedMimeType, TrustedContentLength, TrustedContentHash, TrustedProcessingVersion,
         TrustedCreatedAtUtc, StorageStatus, ScanStatus, ScanProvider, ScanStartedAtUtc,
         ScanCompletedAtUtc, SortOrder, IsDeleted, UploadedByUserId, DeletedByUserId, DeletedAtUtc,
         CreatedAtUtc, UpdatedAtUtc)
    OUTPUT inserted.Id, inserted.PublicId, inserted.SortOrder INTO @Assets
    SELECT NEWID(), @ProjectId, CASE WHEN f.N >= 7 THEN 0 ELSE 1 END,
           CASE WHEN f.N >= 7 THEN N'smoke.png' ELSE N'smoke.pdf' END,
           CASE WHEN f.N >= 7 THEN N'image/png' ELSE N'application/pdf' END, 123, @Hash,
           CASE WHEN f.N >= 7 THEN 100 END, CASE WHEN f.N >= 7 THEN 80 END,
           N'fp-project-quarantine', names.ObjectName, N'"quarantine"', N'quarantine-version',
           CASE WHEN f.N IN (1, 2, 6) THEN N'fp-project-trusted' END,
           CASE WHEN f.N IN (1, 2, 6) THEN names.ObjectName END,
           CASE WHEN f.N IN (1, 2, 6) THEN N'"trusted"' END,
           CASE WHEN f.N IN (1, 2, 6) THEN N'trusted-version' END,
           CASE WHEN f.N IN (1, 2, 6) THEN N'application/pdf' END,
           CASE WHEN f.N IN (1, 2, 6) THEN 123 END,
           CASE WHEN f.N IN (1, 2, 6) THEN @Hash END,
           CASE WHEN f.N IN (1, 2, 6) THEN N'pdf-copy-v1' END,
           CASE WHEN f.N IN (1, 2, 6) THEN @Old END,
           CASE WHEN f.N IN (1, 2, 6) THEN 2 ELSE 3 END,
           CASE WHEN f.N IN (1, 2, 6) THEN 1 WHEN f.N = 7 THEN 3 WHEN f.N = 8 THEN 2 ELSE f.N - 1 END,
           1, @Old, @Old, f.N, CASE WHEN f.N IN (2, 6) THEN 1 ELSE 0 END, @UserId,
           CASE WHEN f.N IN (2, 6) THEN @UserId END,
           CASE WHEN f.N = 2 THEN @Old WHEN f.N = 6 THEN @Now END, @Old, @Now
    FROM (VALUES (1), (2), (3), (4), (5), (6), (7), (8)) AS f(N)
    CROSS APPLY (SELECT CONVERT(NVARCHAR(36), @User) + N'/' + LEFT(@Suffix, 30) +
        RIGHT(N'00' + CONVERT(NVARCHAR(2), f.N), 2) +
        CASE WHEN f.N >= 7 THEN N'.png' ELSE N'.pdf' END AS ObjectName) AS names;

    DECLARE @SanitizedHash BINARY(32) = HASHBYTES('SHA2_256', N'sanitized-retention-smoke');
    INSERT dbo.FundingPlatform_ProjectAssetScanEvents
        (EventId, ProjectAssetId, ScanProvider, ProviderEventId, PayloadHash,
         FromStatus, ToStatus, ProviderObservedStatus, QuarantineBlobETag, ReportedContentHash,
         ResultCode, ProviderResultCode, ResultRowVersion, OccurredAtUtc, CreatedAtUtc,
         RevokedTrustedBlobContainer, RevokedTrustedBlobObjectName,
         RevokedTrustedBlobETag, RevokedTrustedBlobVersionId, RevokedTrustedMimeType,
         RevokedTrustedContentLength, RevokedTrustedContentHash, RevokedTrustedPixelWidth,
         RevokedTrustedPixelHeight, RevokedTrustedProcessingVersion, RevokedTrustedCreatedAtUtc)
    SELECT NEWID(), assets.Id, 1, N'retention-revocation-' + CONVERT(NVARCHAR(36), assets.PublicId),
           @Hash, 1, assets.ScanStatus, CASE WHEN fixtures.Fixture = 7 THEN 1 ELSE 2 END,
           assets.QuarantineBlobETag, @Hash,
           CASE WHEN fixtures.Fixture = 7 THEN N'legacy-image-unsanitized' ELSE N'malicious' END,
           CASE WHEN fixtures.Fixture = 7 THEN N'no-threats-found' ELSE N'malicious' END,
           assets.RowVersion, @Old, @Old, N'fp-project-trusted', assets.QuarantineBlobObjectName,
           N'"revoked-trusted"', CASE WHEN fixtures.Fixture = 8 THEN N'exact-revoked-version' END,
           N'image/png', 123, CASE WHEN fixtures.Fixture = 8 THEN @SanitizedHash ELSE @Hash END,
           100, 80, CASE WHEN fixtures.Fixture = 7 THEN N'legacy-unsanitized-v0' ELSE N'skia-4.151.2-image-v1' END,
           @Old
    FROM dbo.FundingPlatform_ProjectAssets AS assets
    JOIN @Assets AS fixtures ON fixtures.Id = assets.Id WHERE fixtures.Fixture IN (7, 8);

    IF EXISTS (SELECT 1 FROM dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates AS c
               JOIN @Assets AS a ON a.PublicId = c.ProjectAssetPublicId WHERE a.Fixture = 1)
        THROW 55930, N'Active trusted content or its quarantine became eligible.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_vw_ProjectAssetRetentionCandidates AS c
        JOIN @Assets AS a ON a.PublicId = c.ProjectAssetPublicId
        WHERE c.RetentionUntilUtc <= @Now) <> 9
        THROW 55931, N'Deleted/terminal eligibility or 24-hour grace drifted.', 1;

    DECLARE @Claims TABLE
        (TaskPublicId UNIQUEIDENTIFIER, ProjectAssetPublicId UNIQUEIDENTIFIER, BlobKind TINYINT,
         BlobContainer NVARCHAR(63), BlobObjectName NVARCHAR(1024), BlobETag NVARCHAR(100),
         BlobVersionId NVARCHAR(200), MimeType NVARCHAR(100), ContentLength BIGINT,
         ContentHash BINARY(32), SourceContentHash BINARY(32), ProcessingVersion NVARCHAR(100),
         RetentionUntilUtc DATETIME2(3), AttemptCount SMALLINT, MaxAttempts SMALLINT,
         LeaseUntilUtc DATETIME2(3), IdentityHash BINARY(32));
    DECLARE @Lease UNIQUEIDENTIFIER = NEWID(), @OtherLease UNIQUEIDENTIFIER = NEWID();
    INSERT @Claims EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
        @BatchSize = 100, @LeaseId = @Lease, @LeaseSeconds = 30, @NowUtc = @Now;
    IF (SELECT COUNT(*) FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId) <> 9
       OR EXISTS (SELECT 1 FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId
                  WHERE c.ContentHash <> CASE WHEN a.Fixture = 8 AND c.BlobKind = 1 THEN @SanitizedHash ELSE @Hash END
                     OR c.ContentLength <> 123 OR c.AttemptCount <> 1
                     OR (NOT (a.Fixture = 8 AND c.BlobKind = 1) AND
                         (c.SourceContentHash IS NOT NULL OR c.ProcessingVersion IS NOT NULL)))
       OR NOT EXISTS (SELECT 1 FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId
                      WHERE a.Fixture = 8 AND c.BlobKind = 1 AND c.SourceContentHash = @Hash
                        AND c.ProcessingVersion = N'skia-4.151.2-image-v1'
                        AND c.BlobVersionId = N'exact-revoked-version')
       OR NOT EXISTS (SELECT 1 FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId
                      WHERE a.Fixture = 7 AND c.BlobKind = 1 AND c.BlobVersionId IS NULL)
        THROW 55932, N'Exact-manifest claims were not materialized.', 1;
    DECLARE @Task UNIQUEIDENTIFIER, @Identity BINARY(32);
    SELECT TOP (1) @Task = c.TaskPublicId, @Identity = c.IdentityHash
    FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId WHERE a.Fixture = 2 AND c.BlobKind = 1;
    DECLARE @Mutations TABLE (Succeeded BIT, Code NVARCHAR(50), ContentDeletedAtUtc DATETIME2(3),
        NextAttemptAtUtc DATETIME2(3), AttemptCount SMALLINT, MaxAttempts SMALLINT, WasReplay BIT);
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
        @TaskPublicId = @Task, @LeaseId = @OtherLease, @IdentityHash = @Identity, @NowUtc = @Now;
    IF EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1)
        THROW 55933, N'A stale lease completed a task.', 1;
    DELETE FROM @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
        @TaskPublicId = @Task, @LeaseId = @Lease, @IdentityHash = @Hash, @NowUtc = @Now;
    IF EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1)
        THROW 55934, N'A changed identity completed a task.', 1;
    DELETE FROM @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
        @TaskPublicId = @Task, @LeaseId = @Lease, @IdentityHash = @Identity, @NowUtc = @Now;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
        @TaskPublicId = @Task, @LeaseId = @Lease, @IdentityHash = @Identity, @NowUtc = @Now;
    IF (SELECT COUNT(*) FROM @Mutations WHERE Succeeded = 1 AND Code = N'completed') <> 2
       OR (SELECT COUNT(*) FROM @Mutations WHERE WasReplay = 1) <> 1
        THROW 55935, N'Completion is not idempotent.', 1;

    SELECT TOP (1) @Task = c.TaskPublicId, @Identity = c.IdentityHash
    FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId WHERE a.Fixture = 3;
    DELETE FROM @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail
        @TaskPublicId = @Task, @LeaseId = @Lease, @IdentityHash = @Identity,
        @ErrorCode = N'blob-deletion-unavailable', @IsRetryable = 1, @NowUtc = @Now;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1 AND Code = N'retry-scheduled'
                   AND NextAttemptAtUtc = DATEADD(SECOND, 60, @Now))
        THROW 55936, N'Retry backoff is invalid.', 1;
    DELETE FROM @Claims;
    INSERT @Claims EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
        @BatchSize = 100, @LeaseId = @OtherLease, @LeaseSeconds = 30, @NowUtc = @Now;
    IF EXISTS (SELECT 1 FROM @Claims c JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId)
        THROW 55937, N'Concurrent claim stole a lease or ignored retry delay.', 1;
    DECLARE @Later DATETIME2(3) = DATEADD(SECOND, 61, @Now);
    DELETE FROM @Claims;
    INSERT @Claims EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
        @BatchSize = 100, @LeaseId = @OtherLease, @LeaseSeconds = 30, @NowUtc = @Later;
    IF NOT EXISTS (SELECT 1 FROM @Claims WHERE TaskPublicId = @Task AND AttemptCount = 2)
        THROW 55938, N'Due retry was not reclaimed.', 1;
    DELETE FROM @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete
        @TaskPublicId = @Task, @LeaseId = @Lease, @IdentityHash = @Identity, @NowUtc = @Later;
    IF EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1)
        THROW 55943, N'A previous worker completed a reclaimed task.', 1;
    DELETE FROM @Mutations;
    INSERT @Mutations EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail
        @TaskPublicId = @Task, @LeaseId = @OtherLease, @IdentityHash = @Identity,
        @ErrorCode = N'blob-identity-conflict', @IsRetryable = 0, @NowUtc = @Later;
    IF NOT EXISTS (SELECT 1 FROM @Mutations WHERE Succeeded = 1 AND Code = N'failed')
        THROW 55939, N'Identity conflict did not fail closed.', 1;
    IF (SELECT COUNT(*) FROM dbo.FundingPlatform_ProjectAssetContentRetentionAttempts AS attempts
        JOIN dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks ON tasks.Id = attempts.TaskId
        WHERE tasks.PublicId = @Task) <> 2
        THROW 55940, N'Attempt history is incomplete.', 1;

    /* A crashed worker is reclaimed at most eight times, then terminalized. */
    SELECT @Task = c.TaskPublicId FROM @Claims c
    JOIN @Assets a ON a.PublicId = c.ProjectAssetPublicId WHERE a.Fixture = 4;
    DECLARE @Round INT = 0;
    WHILE @Round < 7
    BEGIN
        SET @Later = DATEADD(SECOND, 31, @Later);
        DELETE FROM @Claims;
        INSERT @Claims EXEC dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim
            @BatchSize = 100, @LeaseId = @OtherLease, @LeaseSeconds = 30, @NowUtc = @Later;
        SET @Round += 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetContentRetentionTasks
                   WHERE PublicId = @Task AND Status = 3 AND AttemptCount = 8
                     AND LastErrorCode = N'retries-exhausted' AND LeaseUntilUtc IS NULL)
       OR EXISTS (SELECT 1 FROM dbo.FundingPlatform_ProjectAssetContentRetentionAttempts AS attempts
                  JOIN dbo.FundingPlatform_ProjectAssetContentRetentionTasks AS tasks ON tasks.Id = attempts.TaskId
                  WHERE tasks.PublicId = @Task AND attempts.FinishedAtUtc IS NULL)
        THROW 55944, N'Abandoned attempts exceeded their cap or left open audit receipts.', 1;

    /* 039 intentionally excludes incoming uploads and orphan promotions without persisted identities. */
    IF EXISTS (SELECT 1 FROM sys.database_permissions
               WHERE major_id IN
                   (OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim'),
                    OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete'),
                    OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail'))
                 AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_ApiRuntimeRole'))
        THROW 55941, N'API may not execute retention commands.', 1;
    IF (SELECT COUNT(*) FROM sys.database_permissions
        WHERE major_id IN
            (OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Claim'),
             OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Complete'),
             OBJECT_ID(N'dbo.FundingPlatform_usp_ProjectAssetContentRetention_Fail'))
          AND grantee_principal_id = DATABASE_PRINCIPAL_ID(N'FundingPlatform_GeneralWorkerRole')
          AND permission_name = N'EXECUTE' AND state = N'G') <> 3
        THROW 55942, N'Worker retention grants are incomplete.', 1;
    IF @InitialTransactionCount = 0 ROLLBACK TRANSACTION;
    ELSE ROLLBACK TRANSACTION FP_Smoke039;
END TRY
BEGIN CATCH
    IF @InitialTransactionCount = 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    ELSE IF @InitialTransactionCount > 0 AND XACT_STATE() = 1 ROLLBACK TRANSACTION FP_Smoke039;
    THROW;
END CATCH;
