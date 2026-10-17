-- Step 2. Run on EACH SQL Server as sysadmin:
--   sqlcmd -E -C -i 02-sql-login.sql -v GmsaLogin="CONTOSO\gmsa-sqlmcp$"
-- Creates a server login and a server-role membership. No database, no user, no other object.
-- ##MS_ServerPerformanceStateReader## exists from SQL Server 2022; older versions: see the README (VIEW SERVER STATE).
IF SUSER_ID(N'$(GmsaLogin)') IS NULL
    CREATE LOGIN [$(GmsaLogin)] FROM WINDOWS WITH DEFAULT_DATABASE = [master];
IF IS_SRVROLEMEMBER(N'##MS_ServerPerformanceStateReader##', N'$(GmsaLogin)') = 0
    ALTER SERVER ROLE [##MS_ServerPerformanceStateReader##] ADD MEMBER [$(GmsaLogin)];
SELECT @@SERVERNAME AS server, p.name AS login, r.name AS server_role,
       IS_SRVROLEMEMBER('sysadmin', p.name) AS is_sysadmin
FROM sys.server_principals p
LEFT JOIN sys.server_role_members m ON m.member_principal_id = p.principal_id
LEFT JOIN sys.server_principals r ON r.principal_id = m.role_principal_id
WHERE p.name = N'$(GmsaLogin)';
