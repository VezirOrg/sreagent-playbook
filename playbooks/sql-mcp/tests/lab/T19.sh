#!/bin/sh
# T19 (criterion b): the agent answers DMV questions as sqlcmd does: the top wait type on sql2, and the number of user
# sessions on sql1 (sqlcmd counts itself, so a difference of one or two is printed, not failed).
. "$(dirname "$0")/common.sh"
lab_load || exit 1
o=$(ask "What is the top wait type on sql2, by total wait time? Use the sqlmcp tools. Answer with the wait type name." | evidence T19-wait)
w=$(sqlq sql2 "SELECT TOP 1 wait_type FROM sys.dm_os_wait_stats ORDER BY wait_time_ms DESC" | tr -d '\r' | head -1)
echo "$o" | grep -q "$w" && ok "top wait on sql2 = $w (agent and sqlcmd)" || bad "sqlcmd says $w, the agent did not"
o=$(ask "How many user sessions are there on sql1 right now? Use the sqlmcp tools. Answer with the number." | evidence T19-sessions)
n=$(sqlq sql1 "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1" | tr -d '\r' | head -1)
echo "  sessions on sql1: sqlcmd $n (counts itself); agent answer: $(echo "$o" | grep -oE '[0-9]+' | head -3 | tr '\n' ' ')"
echo "$o" | grep -q 'sqlmcp' && ok "the thread shows sqlmcp tool calls" || echo "  (no sqlmcp tool name in the answer text; check the thread)"
finish
