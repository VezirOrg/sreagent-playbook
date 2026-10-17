#!/bin/sh
# T12: nothing on the SQL Servers but the login: the gMSA is in exactly one server role
# (##MS_ServerPerformanceStateReader##), is not sysadmin, owns no database, and has no user in any database.
. "$(dirname "$0")/common.sh"
lab_load || exit 1
login="$netbios\\gmsa-sqlmcp\$"
for s in $sqls; do
  check "$s login exists" "$(sqlq "$s" "SELECT COUNT(*) FROM sys.server_principals WHERE name = N'$login'")" "1"
  check "$s server roles" "$(sqlq "$s" "SELECT r.name FROM sys.server_role_members m JOIN sys.server_principals r ON r.principal_id = m.role_principal_id JOIN sys.server_principals p ON p.principal_id = m.member_principal_id WHERE p.name = N'$login'")" "##MS_ServerPerformanceStateReader##"
  check "$s sysadmin" "$(sqlq "$s" "SELECT IS_SRVROLEMEMBER('sysadmin', N'$login')")" "0"
  check "$s databases owned" "$(sqlq "$s" "SELECT COUNT(*) FROM sys.databases WHERE owner_sid = SUSER_SID(N'$login')")" "0"
  check "$s database users" "$(sqlq "$s" "DECLARE @n int = 0, @c int, @d sysname, @q nvarchar(400); DECLARE c CURSOR LOCAL FOR SELECT name FROM sys.databases WHERE state = 0; OPEN c; FETCH c INTO @d; WHILE @@FETCH_STATUS = 0 BEGIN SET @q = N'SELECT @c = COUNT(*) FROM ' + QUOTENAME(@d) + N'.sys.database_principals WHERE sid = SUSER_SID(N''$login'')'; EXEC sp_executesql @q, N'@c int OUTPUT', @c OUTPUT; SET @n += @c; FETCH c INTO @d; END; SELECT @n")" "0"
done
finish
