# How the lab plants the problems (T16)

> **Summary.** For the end-to-end test the lab makes a server misbehave in known ways for 70 minutes, then asks the
> SRE Agent to analyse the latest capture and scores its report against what was planted. The load comes from plain
> Windows PowerShell 5.1: copies of the built-in `powershell.exe` renamed `bbleak.exe`, `bbcpu.exe`, `bbdisk.exe` and
> `bbnic.exe`, started by a one-off SYSTEM task. Nothing is installed. The script writes `truth.json` (what ran,
> when) as the ground truth. Lab only: never part of the package.
>
> Script: [`tests/lab/guest/make-trouble.ps1`](../tests/lab/guest/make-trouble.ps1). Scorer:
> [`tests/scoring/score.py`](../tests/scoring/score.py), rules in [`tests/scoring/rubric.md`](../tests/scoring/rubric.md).

## Timeline (minutes after start)

| Plant | Process | When | Intensity | Shows in |
|---|---|---|---|---|
| Memory leak | `bbleak.exe` | 0 → 70 | +600 MiB per hour, one PID (≈ 700 MB in total) | `Process(bbleak)\Private Bytes`, `Working Set`; `Memory\Available MBytes` |
| CPU burst | `bbcpu.exe` | +10, 12 min | one busy thread per logical CPU (machine ≈ 100 %) | `Processor Information(_Total)\% Processor Time`, `Process(bbcpu)\% Processor Time`, queue length |
| Disk latency | `bbdisk.exe` | +32, 6 min | 32 threads of random 4 KiB write-through writes on C: (queue depth 32) | `LogicalDisk(C:)\Avg. Disk sec/Write`, queue lengths, idle time |
| Network burst | `bbnic.exe` | +45, 6 min | 1,400-byte UDP datagrams in a tight loop to a lab host | `Network Interface(*)\Bytes Total/sec` |

**Removed:** a "stall" plant (all CPUs busy for 30 s, twice). Emre closed OPEN-2 for v1.0.0 (decisions P34): the skill
treats 30-second events as blips by design, so they are neither planted nor scored.

## Why renamed copies of powershell.exe

PerfMon names a process instance after its executable. A copy of the built-in host named `bbcpu.exe` makes the CPU
burst appear as `Process(bbcpu)`, so the agent can name the driver, and the scorer can check it. Every load runs
**inside its own bb process** (runspaces, not `Start-Job`, whose child processes would appear as `powershell#1`).

```powershell
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
```

## Start and stop

The test starts the timeline in the background as SYSTEM, so it survives the SSH session:

```powershell
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $dir\make-trouble.ps1 -Run -Scale $Scale"
& schtasks.exe /create /tn '\BbDev\MakeTrouble' /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /tr $cmd /f
& schtasks.exe /run /tn '\BbDev\MakeTrouble'
```

`-Stop` ends everything at once:

```powershell
Get-Process -Name bbleak, bbcpu, bbdisk, bbnic -ErrorAction SilentlyContinue | Stop-Process -Force
& schtasks.exe /delete /tn '\BbDev\MakeTrouble' /f
```

## The critical parts

**Leak** (`bbleak.exe`): every 10 s allocate a block, touch every page so it is really committed, keep a reference.

```powershell
$l = New-Object System.Collections.ArrayList
$step = [int]($LeakMBPerHour * 1MB / 360)            # 360 steps per hour
while ((Get-Date) -lt $end) {
    $b = New-Object byte[] $step
    for ($i = 0; $i -lt $b.Length; $i += 4096) { $b[$i] = 1 }
    [void]$l.Add($b); Start-Sleep 10
}
```

**Parallel work inside one process** (used by `bbcpu.exe` and `bbdisk.exe`):

```powershell
function Invoke-Pool([int]$n, [scriptblock]$body, $arg) {
  $p = [runspacefactory]::CreateRunspacePool(1, $n); $p.Open(); $h = @()
  for ($i = 0; $i -lt $n; $i++) {
    $ps = [powershell]::Create(); $ps.RunspacePool = $p
    [void]$ps.AddScript($body).AddArgument($arg).AddArgument($i); $h += ,@($ps, $ps.BeginInvoke())
  }
  foreach ($x in $h) { [void]$x[0].EndInvoke($x[1]); $x[0].Dispose() }; $p.Close()
}
```

**CPU burst** (`bbcpu.exe`): one busy thread per logical CPU for 12 minutes.

```powershell
Invoke-Pool $cpus { param($end, $i) while ((Get-Date) -lt $end) { $null = [math]::Sqrt(12345) } } (Get-Date).AddSeconds(720)
```

**Disk latency** (`bbdisk.exe`): 32 threads, each with its own 256 MB file, random 4 KiB writes that bypass the cache.

```powershell
Invoke-Pool 32 { param($end, $i)
  $f = 'C:\BbDev\trouble\io\' + $i + '.bin'
  $fs = New-Object IO.FileStream($f, 'Create', 'ReadWrite', 'None', 4096, [IO.FileOptions]::WriteThrough)
  $fs.SetLength(256MB); $b = New-Object byte[] 4096; $r = New-Object Random($i)
  while ((Get-Date) -lt $end) { $fs.Position = [int64]$r.Next(0, 65535) * 4096; $fs.Write($b, 0, 4096) }
  $fs.Close(); Remove-Item $f
} (Get-Date).AddSeconds(360)
```

**Network burst** (`bbnic.exe`): UDP to the discard port of a lab host in the same VNet.

```powershell
$u = New-Object Net.Sockets.UdpClient; $u.Connect('dc', 9); $b = New-Object byte[] 1400
while ((Get-Date) -lt $end) { for ($i = 0; $i -lt 2000; $i++) { [void]$u.Send($b, $b.Length) } }
$u.Close()
```

## Ground truth and cleanup

- `C:\BbDev\trouble\truth.json` gets one entry per plant with its real start and end time (local time of the server),
  the driver and, for the leak, the planted rate. T16 adds the latest zip's own window (`capture_first`,
  `capture_last`) before scoring.
- Each bb process ends at its end time; `bbleak` is stopped at +70 min; `bbdisk` deletes its files. `-Stop` kills any
  leftover and removes the task. The copies and `truth.json` live in `C:\BbDev`, which is removed at the end of the
  lab work.
- `-Scale 0.03` runs the whole timeline in about two minutes (a dry run of the script itself).
