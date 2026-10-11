# How the lab plants the problems (T16)

> **Summary.** For the end-to-end test the lab makes a server misbehave in known ways for 70 minutes, then asks the
> SRE Agent to analyse the latest capture and scores its report against what was planted. The load comes from plain
> Windows PowerShell 5.1: copies of the built-in `powershell.exe` renamed `bbleak.exe` and `bbcpu.exe`, started by a one-off SYSTEM task. Nothing is installed. The script writes `truth.json` (what ran,
> when) as the ground truth. Lab only: never part of the package.
>
> Script: [`tests/lab/guest/make-trouble.ps1`](../tests/lab/guest/make-trouble.ps1). Scorer:
> [`tests/scoring/score.py`](../tests/scoring/score.py), rules in [`tests/scoring/rubric.md`](../tests/scoring/rubric.md).

## Timeline (minutes after start)

| Plant | Process | When | Intensity | Shows in |
|---|---|---|---|---|
| Memory leak | `bbleak.exe` | 0 → 45 | +600 MiB per hour, one PID (≈ 450 MB in total) | `Process(bbleak)\Private Bytes`, `Working Set`; `Memory\Available MBytes` |
| CPU burst | `bbcpu.exe` | +10, 12 min | one busy thread per logical CPU (machine ≈ 100 %) | `Processor Information(_Total)\% Processor Time`, `Process(bbcpu)\% Processor Time`, queue length |

**Only memory and CPU are planted** (Emre, decisions P43). Removed on the way, each for a reason:
- a 30-s **stall** plant: the skill treats 30-second events as blips by design (OPEN-2 closed, P34);
- a **disk-latency** plant: in four runs it failed to load the disk (an ambiguous `FileStream` constructor in Windows
  PowerShell 5.1, then a scratch volume left full), and it needed an uncached lab data disk (P39, P42);
- a **network** burst: a test process cannot get near the share of an Azure vNIC's bandwidth the skill flags, so
  "network fine" was always the skill's correct verdict.
The skill itself still checks disk and network; only the test does not plant them.

Before a run is scored, the plants are checked in the capture (P42): CPU above 85 % for most of the burst, the leaking
process present and growing. A run whose plant did not take effect is invalid, not scored.

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
Get-Process -Name bbleak, bbcpu -ErrorAction SilentlyContinue | Stop-Process -Force
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

**Parallel work inside one process** (used by `bbcpu.exe`):

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

## Ground truth and cleanup

- `C:\BbDev\trouble\truth.json` gets one entry per plant with its real start and end time (local time of the server),
  the driver and, for the leak, the planted rate. T16 adds the latest zip's own window (`capture_first`,
  `capture_last`) before scoring.
- Each bb process ends at its end time; `bbleak` is stopped at +45 min. `-Stop` kills any
  leftover and removes the task. The copies and `truth.json` live in `C:\BbDev`, which is removed at the end of the
  lab work.
- `-Scale 0.03` runs the whole timeline in under two minutes (a dry run of the script itself).
