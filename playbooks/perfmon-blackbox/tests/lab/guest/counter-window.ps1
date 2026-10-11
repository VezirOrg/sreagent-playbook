# Lab verifier (dc): download one capture zip of a machine and report one counter over a time window: samples, max,
# minutes above a threshold, the longest run above it. Used to check that a T16 plant really took effect (P42).
param([Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Blob, [Parameter(Mandatory)][string]$Column,
      [Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To, [double]$Threshold = 0.025, [string]$Container = 'perfmon')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tok = ((Invoke-WebRequest -UseBasicParsing -Headers @{ Metadata = 'true' } 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F').Content | ConvertFrom-Json).access_token
$w = 'C:\BbDev\cw'; Remove-Item $w -Recurse -Force -ErrorAction SilentlyContinue; $null = New-Item -ItemType Directory -Force $w
Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03' } "https://$Account.blob.core.windows.net/$Container/$Blob" -OutFile "$w\c.zip"
[IO.Compression.ZipFile]::ExtractToDirectory("$w\c.zip", "$w\x")
$csv = Get-ChildItem "$w\x" -Filter *.csv | Select-Object -First 1
$lines = [IO.File]::ReadAllLines($csv.FullName)
$hdr = $lines[0].Trim('"') -split '","'
$idx = -1; for ($i = 0; $i -lt $hdr.Count; $i++) { if ($hdr[$i] -like "*$Column") { $idx = $i; break } }
if ($idx -lt 0) { "column not found: $Column"; exit 1 }
$f = [datetime]$From; $t = [datetime]$To; $n = 0; $max = 0; $above = 0; $run = 0; $best = 0; $maxAt = ''
foreach ($l in $lines[1..($lines.Count - 1)]) {
    $c = $l.Trim('"') -split '","'
    $ts = [datetime]::ParseExact($c[0], 'MM/dd/yyyy HH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture)
    if ($ts -lt $f -or $ts -gt $t) { continue }
    $n++; $v = 0.0; [void][double]::TryParse($c[$idx], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)
    if ($v -gt $max) { $max = $v; $maxAt = $ts.ToString('HH:mm:ss') }
    if ($v -gt $Threshold) { $above++; $run++; if ($run -gt $best) { $best = $run } } else { $run = 0 }
}
$iv = 10
"{0} in {1}..{2}: samples {3}, max {4:N4} at {5}, samples above {6}: {7}, longest run above: {8} samples (~{9:N1} min)" -f $hdr[$idx].Substring($hdr[$idx].IndexOf('\', 2)), $From, $To, $n, $max, $maxAt, $Threshold, $above, $best, ($best * $iv / 60)
Remove-Item $w -Recurse -Force -ErrorAction SilentlyContinue
