# Lab verifier (dc, Blob Data Reader): per machine prefix, the number of capture zips and the newest upload time.
param([Parameter(Mandatory)][string]$Account, [string]$Container = 'perfmon')
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$tok = ((Invoke-WebRequest -UseBasicParsing -Headers @{ Metadata = 'true' } 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com%2F').Content | ConvertFrom-Json).access_token
$lr = Invoke-WebRequest -UseBasicParsing -Headers @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03' } "https://$Account.blob.core.windows.net/$Container`?restype=container&comp=list"
[xml]$x = [Text.Encoding]::UTF8.GetString($lr.RawContentStream.ToArray()).TrimStart([char]0xFEFF)
$x.EnumerationResults.Blobs.Blob | Where-Object { $_.Name -like '*.zip' } | Group-Object { ($_.Name -split '/')[0..2] -join '/' } | ForEach-Object {
    $last = ($_.Group | ForEach-Object { [datetime]$_.Properties.'Last-Modified' } | Sort-Object | Select-Object -Last 1).ToUniversalTime()
    '{0}: {1} zips, newest upload {2:yyyy-MM-dd HH:mm:ss}Z' -f $_.Name, $_.Count, $last }
