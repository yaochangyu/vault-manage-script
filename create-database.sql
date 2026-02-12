-- ============================================================================
-- SQL Server 資料庫建立腳本
-- ============================================================================
-- 用途：建立新的 SQL Server 資料庫
-- 使用方式：
--   1. 修改下方的變數設定
--   2. 使用 sqlcmd 執行：
--      sqlcmd -S localhost -U sa -P 'YourPassword' -C -i create-database.sql
-- ============================================================================

-- ============================================================================
-- 設定區（請修改為您的實際需求）
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';
DECLARE @DataSize INT = 100;        -- MB
DECLARE @DataGrowth INT = 50;       -- MB
DECLARE @LogSize INT = 50;          -- MB
DECLARE @LogGrowth INT = 25;        -- MB

-- ============================================================================
-- 1. 檢查並建立資料庫
-- ============================================================================
IF EXISTS (SELECT name FROM sys.databases WHERE name = @DatabaseName)
BEGIN
    PRINT '⚠ 資料庫已存在: ' + @DatabaseName;
    PRINT '跳過建立資料庫，繼續建立資料表...';
    PRINT '';
END
ELSE
BEGIN
    PRINT '開始建立資料庫: ' + @DatabaseName;
    PRINT '';

    -- 建立資料庫
    DECLARE @CreateDbSql NVARCHAR(MAX) = N'
    CREATE DATABASE [' + @DatabaseName + N']
    ON PRIMARY
    (
        NAME = ''' + @DatabaseName + N'_Data'',
        FILENAME = ''/var/opt/mssql/data/' + @DatabaseName + N'.mdf'',
        SIZE = ' + CAST(@DataSize AS NVARCHAR) + N'MB,
        FILEGROWTH = ' + CAST(@DataGrowth AS NVARCHAR) + N'MB
    )
    LOG ON
    (
        NAME = ''' + @DatabaseName + N'_Log'',
        FILENAME = ''/var/opt/mssql/data/' + @DatabaseName + N'_log.ldf'',
        SIZE = ' + CAST(@LogSize AS NVARCHAR) + N'MB,
        FILEGROWTH = ' + CAST(@LogGrowth AS NVARCHAR) + N'MB
    );';

    EXEC sp_executesql @CreateDbSql;
    PRINT '✓ 資料庫建立成功: ' + @DatabaseName;
    PRINT '';
END
GO

PRINT '============================================================';
PRINT '資料庫資訊：';
PRINT '============================================================';
GO

-- ============================================================================
-- 2. 顯示資料庫資訊
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';

SELECT
    name AS DatabaseName,
    database_id AS DatabaseID,
    create_date AS CreateDate,
    compatibility_level AS CompatibilityLevel,
    collation_name AS Collation,
    state_desc AS State,
    recovery_model_desc AS RecoveryModel
FROM sys.databases
WHERE name = @DatabaseName;

-- ============================================================================
-- 3. 顯示檔案資訊
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';
DECLARE @UseDatabaseSql NVARCHAR(MAX) = N'USE [' + @DatabaseName + N'];';
EXEC sp_executesql @UseDatabaseSql;

SELECT
    name AS FileName,
    type_desc AS FileType,
    CAST(size * 8.0 / 1024 AS DECIMAL(10,2)) AS SizeMB,
    CASE
        WHEN is_percent_growth = 1 THEN CAST(growth AS VARCHAR(20)) + '%'
        ELSE CAST(CAST(growth * 8.0 / 1024 AS DECIMAL(10,2)) AS VARCHAR(20)) + ' MB'
    END AS Growth
FROM sys.database_files;

PRINT '';
PRINT '✓ 資料庫建立完成！';
PRINT '============================================================';
GO

-- ============================================================================
-- 4. 建立會員資料表
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';
DECLARE @UseDatabaseSql NVARCHAR(MAX) = N'USE [' + @DatabaseName + N'];';
EXEC sp_executesql @UseDatabaseSql;

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Members]') AND type = 'U')
BEGIN
    PRINT '';
    PRINT '建立會員資料表...';

    CREATE TABLE [dbo].[Members]
    (
        MemberID INT IDENTITY(1,1) PRIMARY KEY,
        Username NVARCHAR(50) NOT NULL UNIQUE,
        Email NVARCHAR(100) NOT NULL,
        FullName NVARCHAR(100) NOT NULL,
        PhoneNumber NVARCHAR(20),
        CreateDate DATETIME NOT NULL DEFAULT GETDATE(),
        Status NVARCHAR(20) NOT NULL DEFAULT 'Active',
        CONSTRAINT CK_Members_Status CHECK (Status IN ('Active', 'Inactive', 'Suspended'))
    );

    PRINT '✓ 會員資料表建立成功';
END
ELSE
BEGIN
    PRINT '⚠ 會員資料表已存在';
END
GO

-- ============================================================================
-- 5. 插入測試會員資料（5 筆）
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';
DECLARE @UseDatabaseSql NVARCHAR(MAX) = N'USE [' + @DatabaseName + N'];';
EXEC sp_executesql @UseDatabaseSql;

IF NOT EXISTS (SELECT * FROM [dbo].[Members])
BEGIN
    PRINT '';
    PRINT '插入測試會員資料...';

    INSERT INTO [dbo].[Members] (Username, Email, FullName, PhoneNumber, Status)
    VALUES
        ('john_doe', 'john.doe@example.com', 'John Doe', '0912-345-678', 'Active'),
        ('jane_smith', 'jane.smith@example.com', 'Jane Smith', '0923-456-789', 'Active'),
        ('bob_wilson', 'bob.wilson@example.com', 'Bob Wilson', '0934-567-890', 'Active'),
        ('alice_brown', 'alice.brown@example.com', 'Alice Brown', '0945-678-901', 'Inactive'),
        ('charlie_davis', 'charlie.davis@example.com', 'Charlie Davis', '0956-789-012', 'Active');

    PRINT '✓ 已插入 5 筆測試會員資料';
END
ELSE
BEGIN
    PRINT '⚠ 會員資料表已有資料，跳過插入';
END
GO

-- ============================================================================
-- 6. 顯示會員資料
-- ============================================================================
DECLARE @DatabaseName NVARCHAR(128) = 'MyAppDB';
DECLARE @UseDatabaseSql NVARCHAR(MAX) = N'USE [' + @DatabaseName + N'];';
EXEC sp_executesql @UseDatabaseSql;

PRINT '';
PRINT '============================================================';
PRINT '會員資料列表：';
PRINT '============================================================';

SELECT
    MemberID,
    Username,
    Email,
    FullName,
    PhoneNumber,
    CreateDate,
    Status
FROM [dbo].[Members]
ORDER BY MemberID;

PRINT '';
PRINT '✓ 資料庫、資料表與測試資料建立完成！';
PRINT '============================================================';
PRINT '';
PRINT '後續步驟：';
PRINT '1. 建立使用者（Login 和 User）';
PRINT '2. 授予適當的權限';
PRINT '';
PRINT '建議使用 sql-permission.sh 管理使用者權限';
PRINT '============================================================';
GO
