<#
make-trouble.ps1 (lab only, test plan T16; never shipped): plants known problems that the recorder's counter set can
show, and writes the ground truth (JSON) for the scorer. Windows PowerShell 5.1. Synthetic: process names are
bb* copies of powershell.exe in C:\BbDev\trouble.

Timeline (minutes after start; -Scale shrinks it for a dry run):
  leak   bbleak.exe grows its private bytes by LeakMBPerHour for the whole run (one PID)
  cpu    +10 for 12 min: bbcpu.exe spins one thread per logical CPU (machine CPU >= 95 %)
  stall  +25 and +55 for 30 s: bbstall.exe spins every CPU (the OPEN-2 case: recurring short stalls)
  disk   +32 for 6 min: bbdisk.exe random 4 KiB write-through I/O on C: (latency episode)
  nic    +45 for 6 min: bbnic.exe sends UDP datagrams to dc (Bytes Total/sec burst)
  end    +70
  -Start              run the timeline in the background (a scheduled task as SYSTEM) and return
  -Status             print the ground truth written so far
  -Stop               stop every bb* process and remove the task
#>
param([switch]$Start, [switch]$Status, [switch]$Stop, [switch]$Run, [double]$Scale = 1.0, [int]$LeakMBPerHour = 600,
      [string]$Target = 'dc')
$ErrorActionPreference = 'Stop'
$dir = 'C:\BbDev\trouble'
$truth = Join-Path $dir 'truth.json'

function Copy-Host([string]$Name) {
    $exe = Join-Path $dir "$Name.exe"
    if (-not (Test-Path $exe)) { Copy-Item "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" $exe }
    return $exe
}
function Start-Bb([string]$Name, [string]$Script) {
    $exe = Copy-Host $Name
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    return Start-Process -FilePath $exe -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $enc -WindowStyle Hidden -PassThru
}
function Now { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
function Save($t) { $t | ConvertTo-Json -Depth 6 | Set-Content -Path $truth -Encoding ASCII }

if ($Stop) {
    Get-Process -Name bbleak, bbcpu, bbstall, bbdisk, bbnic -ErrorAction SilentlyContinue | Stop-Process -Force
    & schtasks.exe /delete /tn '\BbDev\MakeTrouble' /f 2>&1 | Out-Null
    'stopped'
    exit 0
}
if ($Status) { if (Test-Path $truth) { Get-Content $truth } else { 'no ground truth yet' }; exit 0 }
if ($Start) {
    $null = New-Item -ItemType Directory -Force -Path $dir
    Copy-Item $PSCommandPath (Join-Path $dir 'make-trouble.ps1') -Force
    $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dir\make-trouble.ps1 -Run -Scale $Scale -LeakMBPerHour $LeakMBPerHour -Target $Target"
    & schtasks.exe /create /tn '\BbDev\MakeTrouble' /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /tr $cmd /f | Out-Null
    & schtasks.exe /run /tn '\BbDev\MakeTrouble' | Out-Null
    "started at $(Now) (scale $Scale)"
    exit 0
}
if (-not $Run) { 'use -Start, -Status or -Stop'; exit 2 }

$null = New-Item -ItemType Directory -Force -Path $dir
$cpus = [Environment]::ProcessorCount
$m = 60 * $Scale   # seconds per timeline minute
$t = [ordered]@{ host = $env:COMPUTERNAME.ToLowerInvariant(); utc_offset = ([TimeZoneInfo]::Local.BaseUtcOffset.ToString()); started = (Now); cpus = $cpus; problems = @() }
Save $t
$spin = "`$e=(Get-Date).AddSeconds({0}); `$j=1..{1} | % {{ Start-Job {{ param(`$x) while((Get-Date) -lt `$x){{ `$null=[math]::Sqrt(12345) }} }} -ArgumentList `$e }}; `$j | Wait-Job | Out-Null"
# leak: allocate and touch memory every 10 s, kept referenced (one PID for the whole run)
$leakSec = [int](70 * $m)
$leak = Start-Bb 'bbleak' ("`$l=New-Object System.Collections.ArrayList; `$end=(Get-Date).AddSeconds($leakSec); `$step=[int]($LeakMBPerHour*1MB/360); while((Get-Date) -lt `$end){ `$b=New-Object byte[] `$step; for(`$i=0;`$i -lt `$b.Length;`$i+=4096){`$b[`$i]=1}; [void]`$l.Add(`$b); Start-Sleep 10 }")
$t.problems += [ordered]@{ id = 'leak'; process = 'bbleak'; counter = 'Private Bytes'; per_hour_bytes = $LeakMBPerHour * 1MB; from = (Now); pid = $leak.Id }
Save $t
$plan = @(@{ at = 10; id = 'cpu' }, @{ at = 25; id = 'stall' }, @{ at = 32; id = 'disk' }, @{ at = 45; id = 'nic' }, @{ at = 55; id = 'stall' }, @{ at = 70; id = 'end' })
$t0 = Get-Date
foreach ($p in $plan) {
    $wait = $t0.AddSeconds($p.at * $m) - (Get-Date)
    if ($wait.TotalSeconds -gt 0) { Start-Sleep -Seconds ([int]$wait.TotalSeconds) }
    switch ($p.id) {
        'cpu' {
            $d = [int](12 * $m); $from = Now
            $pr = Start-Bb 'bbcpu' ($spin -f $d, $cpus); $pr.WaitForExit()
            $t.problems += [ordered]@{ id = 'cpu'; driver = 'bbcpu'; counter = 'Processor Information\% Processor Time'; from = $from; to = (Now); minutes = 12 * $Scale }
        }
        'stall' {
            $from = Now
            $pr = Start-Bb 'bbstall' ($spin -f 30, $cpus); $pr.WaitForExit()
            $st = @($t.problems | Where-Object { $_.id -eq 'stall' })
            if (-not $st.Count) { $t.problems += [ordered]@{ id = 'stall'; driver = 'bbstall'; episodes = @() }; $st = @($t.problems | Where-Object { $_.id -eq 'stall' }) }
            $st[0].episodes += [ordered]@{ from = $from; to = (Now); seconds = 30 }
        }
        'disk' {
            $d = [int](6 * $m); $from = Now
            $io = "`$e=(Get-Date).AddSeconds($d); `$j=1..8 | % { Start-Job { param(`$x,`$n) `$f='C:\BbDev\trouble\io'+`$n+'.bin'; `$fs=New-Object IO.FileStream(`$f,'Create','ReadWrite','None',4096,[IO.FileOptions]::WriteThrough); `$fs.SetLength(1GB); `$b=New-Object byte[] 4096; `$r=New-Object Random; while((Get-Date) -lt `$x){ `$fs.Position=[int64]`$r.Next(0,262143)*4096; `$fs.Write(`$b,0,4096); `$fs.Flush(`$true) }; `$fs.Close(); Remove-Item `$f } -ArgumentList `$e,`$_ }; `$j | Wait-Job | Out-Null"
            $pr = Start-Bb 'bbdisk' $io; $pr.WaitForExit()
            $t.problems += [ordered]@{ id = 'disk'; driver = 'C:'; counter = 'LogicalDisk\Avg. Disk sec/Write'; from = $from; to = (Now); minutes = 6 * $Scale }
        }
        'nic' {
            $d = [int](6 * $m); $from = Now
            $net = "`$e=(Get-Date).AddSeconds($d); `$u=New-Object Net.Sockets.UdpClient; `$u.Connect('$Target',9); `$b=New-Object byte[] 1400; while((Get-Date) -lt `$e){ for(`$i=0;`$i -lt 2000;`$i++){ [void]`$u.Send(`$b,`$b.Length) } }; `$u.Close()"
            $pr = Start-Bb 'bbnic' $net; $pr.WaitForExit()
            $t.problems += [ordered]@{ id = 'nic'; driver = 'bbnic'; counter = 'Network Interface\Bytes Total/sec'; from = $from; to = (Now); minutes = 6 * $Scale }
        }
        'end' {
            $t.problems[0].to = Now
            Get-Process -Name bbleak -ErrorAction SilentlyContinue | Stop-Process -Force
            $t.ended = Now
        }
    }
    Save $t
}
