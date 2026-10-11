# T12 in-guest (Windows PowerShell 5.1): with the machine's OWN token, PUT into another machine's prefix -> 403,
# PUT outside the prefix -> 403, GET and LIST (own prefix included) -> 403, PUT into its own prefix -> 201 (control).
$ErrorActionPreference = 'Stop'
. 'C:\ProgramData\PerfmonBlackbox\bin\PerfmonBlackbox.Common.ps1'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$cfg = Get-BbConfig; $m = Get-BbMachineInfo; $tok = (Get-BbToken).Token
$acct = ($cfg['StorageAccountResourceId'] -split '/')[-1]; $c = $cfg['ContainerName']
$base = "https://$acct.blob.core.windows.net/$c"
$h = @{ Authorization = "Bearer $tok"; 'x-ms-version' = '2023-11-03' }
function Code([string]$Method, [string]$Url, [switch]$Body) {
    $hh = $h.Clone(); if ($Body) { $hh['x-ms-blob-type'] = 'BlockBlob' }
    try {
        if ($Body) { $r = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $Url -Headers $hh -Body ([Text.Encoding]::ASCII.GetBytes('t12')) }
        else { $r = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $Url -Headers $hh }
        return [int]$r.StatusCode
    } catch [System.Net.WebException] { if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }; return -1 }
}
$own = "$($m.Prefix)/t12/probe.txt"
$parts = $m.Prefix.Split('/')
$other = "$($parts[0])/$($parts[1])/othermachine/t12/probe.txt"
$cases = @(
    @('PUT another machine prefix', 'PUT', "$base/$other", $true, 403),
    @('PUT a prefix that only starts like ours', 'PUT', "$base/$($m.Prefix)x/t12/probe.txt", $true, 403),
    @('PUT outside any machine prefix', 'PUT', "$base/t12-probe.txt", $true, 403),
    @('LIST the container', 'GET', "$base`?restype=container&comp=list", $false, 403),
    @('LIST own prefix', 'GET', "$base`?restype=container&comp=list&prefix=$([uri]::EscapeDataString($m.Prefix + '/'))", $false, 403),
    @('PUT own prefix (control)', 'PUT', "$base/$own", $true, 201),
    @('GET own blob', 'GET', "$base/$own", $false, 403),
    @('DELETE own blob', 'DELETE', "$base/$own", $false, 403))
$fail = 0
foreach ($k in $cases) {
    $got = Code $k[1] $k[2] -Body:$k[3]
    $okk = ($got -eq $k[4])
    if (-not $okk) { $fail = 1 }
    '{0} {1}: HTTP {2} (expected {3})' -f $(if ($okk) { 'ok  ' } else { 'FAIL' }), $k[0], $got, $k[4]
}
"identity: $($m.Kind)"
if ($fail) { 'RESULT: FAIL' } else { 'RESULT: PASS' }
