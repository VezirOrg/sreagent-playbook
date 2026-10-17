# Step 4. Run on the MCP host as a local admin (Windows PowerShell 5.1). Writes the Data API builder configuration:
#   <ConfigDir>\dab-config.json   runtime + a PLACEHOLDER data source (no entities; never contacted)
#   <ConfigDir>\<server>.json     one file per SQL Server: its 7 DMV views, read only, cache off
# Only tokens issued by Entra for the app -AppId (v2, audience = the app ID) that carry the app role -Role may read; the
# client names the role in the X-MS-API-ROLE header. Existing JSON files are first copied to <ConfigDir>\backup-<time>.
# Then restart Data API builder: Stop-ScheduledTask <task>; stop the Microsoft.DataApiBuilder process; Start-ScheduledTask.
#
# Why a placeholder root: every server is in its own file, so a server can be taken out by renaming its file to .off
# (a listed file that does not exist is skipped SILENTLY; see the README). Data API builder 2.1.5 rejects a root without a
# data source, so the root gets one with an unresolvable name and no entities. RE-TEST THIS AFTER EVERY DAB UPGRADE.
#   -Servers sql1,sql2      SQL Server host names (short names, in -Domain); one file each
#   -TenantId, -AppId       the Entra tenant and the app created by admin/entra-setup
#   -AllowedHosts           host names and addresses clients may use; default: this computer's name, FQDN and IPv4
param([Parameter(Mandatory)][string[]]$Servers, [Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$AppId,
      [string]$Domain = $env:USERDNSDOMAIN, [string]$Role = 'MCP.Read', [string]$ConfigDir = 'C:\dab\config',
      [string[]]$AllowedHosts)
$ErrorActionPreference = 'Stop'
# powershell -File passes 'a,b' as one string: split every list parameter on commas
$Servers = @($Servers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$AllowedHosts = @($AllowedHosts | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $Domain) { throw 'Pass -Domain <dns domain of the SQL Servers>.' }
$Domain = $Domain.ToLower()
if (-not $AllowedHosts.Count) {
  $me = $env:COMPUTERNAME.ToLower()
  $AllowedHosts = @($me, "$me.$Domain") + @(Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual -ErrorAction SilentlyContinue | ForEach-Object IPAddress)
}
$Audience = $AppId                                              # v2 token: aud = the app's client ID
$Issuer   = "https://login.microsoftonline.com/$TenantId/v2.0"  # v2 issuer
$Views = [ordered]@{   # entity suffix = sys object, key columns
  wait_stats    = 'sys.dm_os_wait_stats',           @('wait_type')
  perf_counters = 'sys.dm_os_performance_counters', @('object_name', 'counter_name', 'instance_name')
  sys_memory    = 'sys.dm_os_sys_memory',           @('total_physical_memory_kb')
  memory_clerks = 'sys.dm_os_memory_clerks',        @('memory_clerk_address')
  sessions      = 'sys.dm_exec_sessions',           @('session_id')
  requests      = 'sys.dm_exec_requests',           @('session_id', 'request_id')
  query_stats   = 'sys.dm_exec_query_stats',        @('sql_handle', 'statement_start_offset', 'statement_end_offset', 'plan_handle')
}
$Columns = @{   # all columns of each view (SQL Server 2025, same on sql1/sql2), so describe_entities lists them (K-FIELDS)
  wait_stats = 'wait_type waiting_tasks_count wait_time_ms max_wait_time_ms signal_wait_time_ms'
  perf_counters = 'object_name counter_name instance_name cntr_value cntr_type'
  sys_memory = 'total_physical_memory_kb available_physical_memory_kb total_page_file_kb available_page_file_kb system_cache_kb kernel_paged_pool_kb kernel_nonpaged_pool_kb system_high_memory_signal_state system_low_memory_signal_state system_memory_state_desc'
  memory_clerks = 'memory_clerk_address type name memory_node_id pages_kb virtual_memory_reserved_kb virtual_memory_committed_kb awe_allocated_kb shared_memory_reserved_kb shared_memory_committed_kb page_size_in_bytes page_allocator_address host_address parent_memory_broker_type'
  sessions = 'session_id login_time host_name program_name host_process_id client_version client_interface_name security_id login_name nt_domain nt_user_name status context_info cpu_time memory_usage total_scheduled_time total_elapsed_time endpoint_id last_request_start_time last_request_end_time reads writes logical_reads is_user_process text_size language date_format date_first quoted_identifier arithabort ansi_null_dflt_on ansi_defaults ansi_warnings ansi_padding ansi_nulls concat_null_yields_null transaction_isolation_level lock_timeout deadlock_priority row_count prev_error original_security_id original_login_name last_successful_logon last_unsuccessful_logon unsuccessful_logons group_id database_id authenticating_database_id open_transaction_count page_server_reads contained_availability_group_id'
  requests = 'session_id request_id start_time status command sql_handle statement_start_offset statement_end_offset plan_handle database_id user_id connection_id blocking_session_id wait_type wait_time last_wait_type wait_resource open_transaction_count open_resultset_count transaction_id context_info percent_complete estimated_completion_time cpu_time total_elapsed_time scheduler_id task_address reads writes logical_reads text_size language date_format date_first quoted_identifier arithabort ansi_null_dflt_on ansi_defaults ansi_warnings ansi_padding ansi_nulls concat_null_yields_null transaction_isolation_level lock_timeout deadlock_priority row_count prev_error nest_level granted_query_memory executing_managed_code group_id query_hash query_plan_hash statement_sql_handle statement_context_id dop parallel_worker_count external_script_request_id is_resumable page_resource page_server_reads dist_statement_id label'
  query_stats = 'sql_handle statement_start_offset statement_end_offset plan_generation_num plan_handle creation_time last_execution_time execution_count total_worker_time last_worker_time min_worker_time max_worker_time total_physical_reads last_physical_reads min_physical_reads max_physical_reads total_logical_writes last_logical_writes min_logical_writes max_logical_writes total_logical_reads last_logical_reads min_logical_reads max_logical_reads total_clr_time last_clr_time min_clr_time max_clr_time total_elapsed_time last_elapsed_time min_elapsed_time max_elapsed_time query_hash query_plan_hash total_rows last_rows min_rows max_rows statement_sql_handle statement_context_id total_dop last_dop min_dop max_dop total_grant_kb last_grant_kb min_grant_kb max_grant_kb total_used_grant_kb last_used_grant_kb min_used_grant_kb max_used_grant_kb total_ideal_grant_kb last_ideal_grant_kb min_ideal_grant_kb max_ideal_grant_kb total_reserved_threads last_reserved_threads min_reserved_threads max_reserved_threads total_used_threads last_used_threads min_used_threads max_used_threads total_columnstore_segment_reads last_columnstore_segment_reads min_columnstore_segment_reads max_columnstore_segment_reads total_columnstore_segment_skips last_columnstore_segment_skips min_columnstore_segment_skips max_columnstore_segment_skips total_spills last_spills min_spills max_spills total_num_physical_reads last_num_physical_reads min_num_physical_reads max_num_physical_reads total_page_server_reads last_page_server_reads min_page_server_reads max_page_server_reads total_num_page_server_reads last_num_page_server_reads min_num_page_server_reads max_num_page_server_reads'
}
$Describe = @{   # descriptions for the columns agents filter or sort on
  wait_type = 'Wait type name. Many are benign idle waits (e.g. SOS_WORK_DISPATCHER, SLEEP_TASK); filter them out for real contention.'
  wait_time_ms = 'Cumulative wait time in ms since the last restart or stats clear (includes signal_wait_time_ms).'
  signal_wait_time_ms = 'Part of wait_time_ms spent waiting for CPU after the resource was ready (CPU pressure).'
  waiting_tasks_count = 'Number of waits on this type (cumulative).'
  object_name = 'Counter object, e.g. SQLServer:General Statistics. Text is space-padded (nchar).'
  counter_name = 'Counter name, e.g. User Connections, Batch Requests/sec. Space-padded (nchar).'
  instance_name = 'Counter instance (database name, etc.). Space-padded (nchar).'
  cntr_value = 'Raw counter value. For per-second counters (cntr_type 272696576) it is cumulative: take two samples.'
  system_memory_state_desc = 'OS memory state, e.g. Available physical memory is high/low.'
  pages_kb = 'Memory allocated by this clerk, in KB.'
  is_user_process = '1 = user session, 0 = system session. Filter is_user_process eq true to count user sessions.'
  status = 'running, sleeping, dormant, preconnect (sessions) / running, runnable, suspended, sleeping, background (requests).'
  login_name = 'Login that owns the session.'
  program_name = 'Client program name of the session.'
  host_name = 'Client host name of the session.'
  blocking_session_id = 'Session that blocks this request; 0 or NULL = not blocked.'
  cpu_time = 'CPU time in ms (sessions: total for the session; requests: for this request).'
  total_elapsed_time = 'Elapsed time in ms (requests) / in microseconds (query_stats).'
  command = 'Type of command being processed (SELECT, INSERT, BACKUP DATABASE, ...).'
  execution_count = 'Times the plan has run since it was compiled.'
  total_worker_time = 'Total CPU time in microseconds for all executions of this plan. Top CPU query = order by this.'
  total_logical_reads = 'Total logical reads for all executions of this plan.'
  last_execution_time = 'Last time the plan started executing.'
}
function New-SourceDoc($srv) {
  $ents = [ordered]@{}
  foreach ($k in $Views.Keys) {
    $obj, $keys = $Views[$k]
    $ents["${srv}_$k"] = [ordered]@{
      description = "${srv}: $obj"
      source      = [ordered]@{ object = $obj; type = 'view' }
      fields      = @($Columns[$k] -split ' ' | ForEach-Object {
                      $f = [ordered]@{ name = $_ }
                      if ($Describe.ContainsKey($_)) { $f.description = $Describe[$_] }
                      if ($keys -contains $_) { $f['primary-key'] = $true }
                      $f })
      graphql     = @{ enabled = $false }
      cache       = @{ enabled = $false }
      permissions = @([ordered]@{ role = $Role; actions = @('read') })
    }
  }
  [ordered]@{
    'data-source' = [ordered]@{
      'database-type'     = 'mssql'
      'connection-string' = "Server=$srv.$Domain;Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=sqlmcp-dab"
      health              = @{ name = $srv }
    }
    entities = $ents
  }
}
$root = [ordered]@{
  'data-source' = [ordered]@{                     # placeholder only: never contacted because it has no entities
    'database-type'     = 'mssql'
    'connection-string' = 'Server=dab-placeholder.invalid;Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Application Name=sqlmcp-dab-placeholder'
    health              = [ordered]@{ enabled = $false; name = 'placeholder' }
  }
  'data-source-files' = @($Servers | ForEach-Object { "$_.json" })
  entities = @{}
}
$root['runtime'] = [ordered]@{
  rest    = @{ enabled = $false }
  graphql = @{ enabled = $false }
  mcp     = [ordered]@{
    enabled = $true; path = '/mcp'
    'allowed-hosts' = @($AllowedHosts)
    'dml-tools' = [ordered]@{ 'describe-entities' = $true; 'read-records' = $true; 'aggregate-records' = $true
                              'create-record' = $false; 'update-record' = $false; 'delete-record' = $false; 'execute-entity' = $false }
  }
  host  = [ordered]@{ mode = 'production'; authentication = [ordered]@{ provider = 'EntraId'; jwt = [ordered]@{ audience = $Audience; issuer = $Issuer } } }
  cache = @{ enabled = $false }
}
New-Item -ItemType Directory -Force $ConfigDir | Out-Null
$old = @(Get-ChildItem (Join-Path $ConfigDir '*.json') -ErrorAction SilentlyContinue)
if ($old.Count) {
  $bak = Join-Path $ConfigDir ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force $bak | Out-Null
  $old | Copy-Item -Destination $bak
  "previous files copied to $bak"
}
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $ConfigDir 'dab-config.json'), ($root | ConvertTo-Json -Depth 20), $utf8)
foreach ($s in $Servers) {
  [IO.File]::WriteAllText((Join-Path $ConfigDir "$s.json"), ((New-SourceDoc $s) | ConvertTo-Json -Depth 20), $utf8)
}
Get-ChildItem (Join-Path $ConfigDir '*.json') | Select-Object Name, Length
