<#
LAB TEST helper (never shipped): run a COPY of the live Data API builder configuration on localhost:<Port> as the
calling admin, with anonymous read added to the copy only, so a check needs no token and never touches the live
service. Prints KEY value lines for the lab tests, then stops the copy and deletes it.
  -Mode describe   start the copy, count entities and described fields, read one row per server (T14, T24)
  -Mode off        rename <Off>.json to .off in the copy first: that server must be skipped silently (T21)
  -Mode dead       point <Dead>'s connection string at a name that does not resolve: the copy must NOT start (T22)
  -Version, -Sha256  run the copy with another Data API builder build, downloaded and hash-checked (T24 on upgrade)
Windows PowerShell 5.1.
#>
param([ValidateSet('describe', 'off', 'dead')][string]$Mode = 'describe', [string]$Off, [string]$Dead,
      [string]$Version, [string]$Sha256, [int]$Port = 5001, [string]$Live = 'C:\dab\config', [string]$Bin = 'C:\dab\bin')
$ErrorActionPreference = 'Stop'
$t = 'C:\dab\test'
$tb = 'C:\dab\test-bin'
$proc = $null
try {
  if ($Version) {
    if (-not $Sha256) { throw 'pass -Sha256 with -Version' }
    New-Item -ItemType Directory -Force $tb | Out-Null
    $zip = Join-Path $tb "dab-$Version.zip"
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    Invoke-WebRequest "https://github.com/Azure/data-api-builder/releases/download/v$Version/dab_net10.0_win-x64-$Version.zip" -OutFile $zip -UseBasicParsing
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $Sha256) { throw "SHA-256 mismatch for $Version" }
    Expand-Archive $zip (Join-Path $tb $Version) -Force
    $Bin = Join-Path $tb $Version
  }
  "VERSION $(& (Join-Path $Bin 'Microsoft.DataApiBuilder.exe') --version | Select-Object -Last 1)"
  if (Test-Path $t) { Remove-Item -Recurse -Force $t }
  New-Item -ItemType Directory -Force $t | Out-Null
  Copy-Item (Join-Path $Live '*.json') $t
  $utf8 = New-Object Text.UTF8Encoding $false
  $root = Get-Content (Join-Path $t 'dab-config.json') -Raw | ConvertFrom-Json
  $root.runtime.mcp.'allowed-hosts' = @($root.runtime.mcp.'allowed-hosts') + 'localhost'
  [IO.File]::WriteAllText((Join-Path $t 'dab-config.json'), ($root | ConvertTo-Json -Depth 30), $utf8)
  "ROOT_ENTITIES $(@($root.entities.PSObject.Properties).Count)"
  $servers = @($root.'data-source-files' | ForEach-Object { $_ -replace '\.json$', '' })
  foreach ($s in $servers) {
    $f = Join-Path $t "$s.json"
    $doc = Get-Content $f -Raw | ConvertFrom-Json
    foreach ($e in $doc.entities.PSObject.Properties) {
      $e.Value.permissions = @($e.Value.permissions) + [pscustomobject]@{ role = 'anonymous'; actions = @('read') }
    }
    if ($Mode -eq 'dead' -and $s -eq $Dead) {
      $doc.'data-source'.'connection-string' = $doc.'data-source'.'connection-string' -replace 'Server=[^;]+', 'Server=sqlmcp-dead.invalid'
    }
    [IO.File]::WriteAllText($f, ($doc | ConvertTo-Json -Depth 30), $utf8)
  }
  if ($Mode -eq 'off') { Rename-Item (Join-Path $t "$Off.json") "$Off.json.off" }
  $env:ASPNETCORE_URLS = "http://localhost:$Port"
  $proc = Start-Process -FilePath (Join-Path $Bin 'Microsoft.DataApiBuilder.exe') -ArgumentList 'start', '--config', 'dab-config.json' `
    -WorkingDirectory $t -RedirectStandardOutput (Join-Path $t 'dab.log') -RedirectStandardError (Join-Path $t 'dab.err') -PassThru -NoNewWindow
  $i = 0
  while (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) -and -not $proc.HasExited -and $i -lt 120) { Start-Sleep 1; $i++ }
  $listening = [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
  "LISTENING $(if ($listening) { 'yes' } else { 'no' })"
  if (-not $listening) {
    Start-Sleep 3
    "EXITED $($proc.HasExited)"
    $log = (Get-Content (Join-Path $t 'dab.log'), (Join-Path $t 'dab.err') -ErrorAction SilentlyContinue) -join "`n"
    "LOG_NAMES_DEAD $(if ($log -match 'sqlmcp-dead\.invalid') { 'yes' } else { 'no' })"
    ($log -split "`n" | Select-Object -Last 15) | ForEach-Object { "LOG $_" }
    return
  }
  $url = "http://localhost:$Port/mcp"
  $d = (& C:\sqlmcp\mcp-call.ps1 -Url $url -Tool describe_entities | Select-Object -Skip 1) -join "`n" | ConvertFrom-Json
  $ents = @($d.entities)
  "ENTITIES $($ents.Count)"
  "WITH_FIELDS $(@($ents | Where-Object { @($_.fields).Count -ge 2 }).Count)"
  "DESCRIBED_FIELDS $(@($ents | ForEach-Object { @($_.fields) } | Where-Object { $_.description }).Count)"
  foreach ($s in $servers) {
    if ($Mode -eq 'off' -and $s -eq $Off) { continue }
    $r = (& C:\sqlmcp\mcp-call.ps1 -Url $url -Tool read_records -Arguments ("{""entity"":""${s}_wait_stats"",""first"":1}") | Select-Object -Skip 1) -join "`n"
    "READ ${s}_wait_stats $(if ($r -match 'success') { 'ok' } else { 'FAIL' })"
  }
} finally {
  if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
  Start-Sleep 1
  Remove-Item -Recurse -Force $t, $tb -ErrorAction SilentlyContinue
}
