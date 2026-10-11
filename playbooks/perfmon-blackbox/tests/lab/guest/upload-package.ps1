# Lab (dc, Windows PowerShell 5.1): copy the release's PerfmonBlackbox.zip into the package container (P45), unchanged:
# download from the release URL, check its SHA-256, PUT it with this machine's identity, read it back and compare.
param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Sha256, [Parameter(Mandatory)][string]$Account,
      [string]$Container = 'packages', [string]$Name = 'PerfmonBlackbox.zip', [string]$LocalFile)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$f = 'C:\BbDev\pkg.zip'
if ($LocalFile) { Copy-Item $LocalFile $f -Force } else { Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $f }
$h = (Get-FileHash $f -Algorithm SHA256).Hash
"downloaded sha256 $h"
if ($h -ne $Sha256.ToUpper()) { throw 'SHA-256 differs from the release' }
$tok = ((Invoke-WebRequest -UseBasicParsing -Headers @{ Metadata = 'true' } 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F').Content | ConvertFrom-Json).access_token
$b = [IO.File]::ReadAllBytes($f); $md5 = [Convert]::ToBase64String([Security.Cryptography.MD5]::Create().ComputeHash($b))
$u = "https://$Account.blob.core.windows.net/$Container/$Name"
$r = Invoke-WebRequest -UseBasicParsing -Method Put -Uri $u -Headers @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03'; 'x-ms-blob-type' = 'BlockBlob'; 'Content-MD5' = $md5 } -Body $b -ContentType 'application/zip'
"PUT $($r.StatusCode)"
Invoke-WebRequest -UseBasicParsing -Uri $u -Headers @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03' } -OutFile "$f.back"
"read back sha256 $((Get-FileHash "$f.back" -Algorithm SHA256).Hash)"
Remove-Item $f, "$f.back" -Force
