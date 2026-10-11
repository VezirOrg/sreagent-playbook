# Lab verifier, run on dc (its identity has Storage Blob Data Reader on the container; lab only): list the machine's
# prefix, take the newest -Last zips, check blob metadata (sha256, Content-MD5), manifest hash, PDH header, the 36
# counters, rows vs window, and continuity between consecutive zips (no gap, no overlap). Windows PowerShell 5.1.
param([Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Prefix, [int]$Last = 2, [string]$Container = 'perfmon',
      [int]$Interval = 10, [switch]$AllowIncomplete)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tok = ((Invoke-WebRequest -UseBasicParsing -Headers @{ Metadata = 'true' } 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F').Content | ConvertFrom-Json).access_token
$h = @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03' }
$base = "https://$Account.blob.core.windows.net/$Container"
[xml]$x = (Invoke-WebRequest -UseBasicParsing -Headers $h "$base`?restype=container&comp=list&include=metadata&prefix=$([uri]::EscapeDataString($Prefix + '/'))").Content.TrimStart([char]0xFEFF)
$blobs = @($x.EnumerationResults.Blobs.Blob | Where-Object { $_.Name -like '*.zip' } | Sort-Object { ($_.Name -split '_')[-1] })
"blobs under prefix: $($blobs.Count)"
$fail = 0
$pick = @($blobs | Select-Object -Last $Last)
$work = 'C:\BbDev\verify'; Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue; $null = New-Item -ItemType Directory -Force $work
$prev = $null
$req = Get-Content 'C:\BbDev\src\package\collector\PerfmonBlackbox.counters.txt' | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($b in $pick) {
    $local = Join-Path $work ([IO.Path]::GetFileName($b.Name))
    $r = Invoke-WebRequest -UseBasicParsing -Headers $h "$base/$($b.Name)" -OutFile $local -PassThru
    $sha = (Get-FileHash $local -Algorithm SHA256).Hash.ToLower()
    $md5 = [Convert]::ToBase64String([Security.Cryptography.MD5]::Create().ComputeHash([IO.File]::ReadAllBytes($local)))
    "zip $($b.Name): $((Get-Item $local).Length) B, metadata sha256 ok=$($b.Metadata.sha256 -eq $sha) Content-MD5 ok=$($b.Properties.'Content-MD5' -eq $md5) seq=$($b.Metadata.seq) complete=$($b.Metadata.complete)"
    if ($b.Metadata.sha256 -ne $sha -or $b.Properties.'Content-MD5' -ne $md5) { $fail = 1 }
    $d = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($local)); [IO.Compression.ZipFile]::ExtractToDirectory($local, $d)
    $man = Get-Content (Join-Path $d 'manifest.json') -Raw | ConvertFrom-Json
    $csv = Join-Path $d $man.csv_name
    $okHash = (Get-FileHash $csv -Algorithm SHA256).Hash.ToLower() -eq $man.csv_sha256
    $head = (Get-Content $csv -TotalCount 1)
    $missing = @($req | Where-Object { $p = [regex]::Escape($_).Replace('\(\*\)', '\([^\\]*\)'); $head -notmatch $p })
    $span = ([datetime]$man.last_sample - [datetime]$man.first_sample).TotalSeconds
    $expRows = [math]::Floor($span / $man.interval_s) + 1
    "  manifest: seq $($man.seq) rows $($man.rows) (window expects ~$expRows) $($man.first_sample) .. $($man.last_sample) complete=$($man.complete) gaps=$(@($man.gaps).Count) roll_s=$($man.roll_seconds) buffer_h=$($man.buffer_hours) identity=$($man.identity) csv hash ok=$okHash pdh=$($head.StartsWith('"(PDH-CSV 4.0)')) missing counters=$($missing.Count)"
    foreach ($g in @($man.gaps)) { "  gap $($g.from) .. $($g.to) $($g.seconds) s $($g.cause)" }
    if (-not $okHash -or -not $head.StartsWith('"(PDH-CSV 4.0)') -or $missing.Count) { $fail = 1 }
    if ($man.complete -and [math]::Abs($man.rows - $expRows) -gt [math]::Max(1, 0.01 * $expRows)) { "  rows off by more than 1 %"; $fail = 1 }
    if (-not $man.complete -and -not $AllowIncomplete) { "  incomplete"; $fail = 1 }
    if ($prev) {
        $step = ([datetime]$man.first_sample - [datetime]$prev.last_sample).TotalSeconds
        "  continuity: previous last $($prev.last_sample) -> this first $($man.first_sample) = $step s; window_from = previous last: $($man.window_from -eq $prev.last_sample)"
        if ($step -le 0) { "  OVERLAP"; $fail = 1 }
        if ($step -gt 2 * $man.interval_s -and -not $AllowIncomplete) { "  GAP"; $fail = 1 }
        if ($man.window_from -ne $prev.last_sample) { $fail = 1 }
    }
    $prev = $man
}
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
