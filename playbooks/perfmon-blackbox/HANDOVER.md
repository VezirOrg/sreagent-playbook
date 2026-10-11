# perfmon-blackbox: IMPLEMENTING (session 2): most stages green on vm1 + arc1; T16 vm1 100 (P43); P46 retry committed (rc.8 to build); T18b: identity download proven on Arc; P47/P48 fixed; stability check in flight.


## Session 2 progress (2026-10-11, live; rewritten at close)

- Decisions P20–P47; root R16–R19. Docs (P35, P38): `docs/` analysis-first, tests.md with live statuses.
- **Green:** L01–L09 (+ CI Windows job); T01, T02, T03, T13, T14; **vm1:** T04–T07, T07b, T08, T09–T12, T10c, T15,
  **T16 run 4 = 100** under P43 (plants verified in the capture, P42); **arc1:** T04–T07, T06b–T06e, T09–T12, T10b,
  T15. Wrap proven, storm none, formula P27. Resilience R1 (real DNS outage, no data lost).
- **Lab pre-releases (P29/P31):** rc.1 … rc.7 (rc.7 = P41, rolled out). **P46** (export retries +5/+15 min, Export task
  restart-on-failure) committed 7edede7, L05 green; **rc.8 not built yet** (after T18b, so the package does not change
  under the storage-mode test).
- **T18b (arc1, package from storage):** system-identity download PROVEN on Arc (agent log 21:00:40Z: "from private
  blob using managed identity", downloaded, validated, applied). Three of our defects found on the way, no SAS anywhere:
  P47 API 2022-01-25 dropped `contentManagedIdentity`; P47 addendum stale RBAC Admin condition; **P48** the service
  re-syncs the guest assignment from the definition metadata (a first-party PUT at 21:07 flipped arc1 back to GitHub),
  so the mode is now chosen at generation: `perfmon-blackbox-<kind>-storage` definitions (accepted by the vezir with
  three conditions, in P48). 21:20Z: arc1 switched by the P48 procedure (pbb-arc removed, pbb-arc-storage assigned,
  remediation). Pass = storage download over two refresh cycles with no PUT back.
- **Resume recipe T18b:** `direnv exec . sh playbooks/perfmon-blackbox/tests/lab/T18.sh arc1 storage` (run.sh passes
  only the machine). Lab assignments now: pbb-vm (GitHub), pbb-arc-storage.
- **Next:** T18b → rc.8 (T01, scrub, SHA in decisions first, publish P31) → P46 lab test (hosts block, retry at +5 min,
  0 gaps) → T18c/d/e/f → T16 run 5 (arc1; vm1 after its next export) → T17 → T08/T07b arc1 → T06f part 2 →
  least-privilege agent role (P30) → fresh-eyes deploy; v1.0.0 = Emre's gate.
- Lab extras (register row updated): arc1; vm1 data disk + patchMode; dc identity = lab verifier; lab SP agent admin
  (P30, remove at teardown). Lab auto-shutdown 19:00Z (dc and vm1): restart needs the owner's OK. Skill v2.1 backup in
  `files/` (path in the owner report).

## Brief from session 1 (kept until close)

Playbook: **perfmon-blackbox**. This file is the brief for the next session (opened with
`pj-open PLAYBOOK=perfmon-blackbox`). Read `../../CLAUDE.md`, then `CLAUDE.md`, this file, `decisions.md` (P1–P19),
`docs/design.md` (rev 3, approved) and `docs/test-plan.md` (rev 3).

## Where it stands (2026-10-11, end of session 1)

- **PLAN-OK** (P19): design rev 3 approved with Emre's change. Defaults: `SampleIntervalSeconds` **10**, `MaxSizeMB`
  **512**, `ExportEveryHours` **4** (parameter, guarded by the capacity check R6), prefix `sub/rg/machine`, DINE-granted
  write-only role with ABAC path condition, private endpoint, 30-day lifecycle, package as GitHub Release asset, skill
  v2.1 adapted to the counter set, all three counter groups with G3 auto-detect, R6 capacity check.
- **Counters:** Emre's 36 (unchanged) + G1 (12) + G2 (2) + G3 (6, auto-detected) in `package/files/*.txt`; sanitized
  Data Collector Set template `package/files/PerfmonBlackbox.template.xml` (imports as is: proven on lab18).
- **Nothing of the product is built yet** (no package, policy, infra, export script, skill v2.1, tests beyond
  `tests/lab/measure-buffer.ps1`).
- **OPEN for Emre (P8):** OPEN-1 (rule 6 `link_test`) and OPEN-2 (5-minute VERDICT CEILING vs. a user-named 20–40 s
  stall). Do not change the skill's rule 6 or ceiling until he decides.

## Lab facts learned (use them)

1. **A running circular `.blg` cannot be read.** `relog` fails on the live file *and* on a copy ("Unable to read
   counter information and data from input binary log files"); after `logman stop` it reads fine. So the export (design
   §2.2 step 1) **must** roll the collector: stop → move the file to `pending\` → start, and relog the closed file. The
   gap is the few seconds of the restart and goes into the manifest. Treat design §2.2's "live snapshot" as decided
   by this fact: use the stop/move/start path (T10 then measures the gap).
2. **Import as is works**; logman accepts binary circular with the full 56-counter set; `Segment Max Size` carries the
   512 MB maximum (PLA `SegmentMaxSize`), `Circular: On`.
3. **Bytes per sample at 1 s, vm1 (Standard_B2s_v2, WS2025, IIS without ASP.NET), ~113 processes:** 36-counter set
   ≈ **52.4 KB** (30,081,024 B / 574 samples), full 56-counter set ≈ **66.6 KB** (38,404,096 B / 577). No samples
   dropped at 1 s. Hours in 512 MB: 36 → ≈ 2.85 h at 1 s, ≈ 28 h at 10 s; full → ≈ 2.24 h at 1 s, **≈ 22 h at 10 s**,
   ≈ 34 h at 15 s.
4. **The process-load step failed:** `measure-buffer.ps1 -Action load` (hidden `ping.exe` helpers) did not raise the
   process count (118–122 after "+100"). Fix before measuring `b` in `bytes ≈ a + b × processes` (e.g. helpers that
   stay alive: `Start-Process cmd -ArgumentList '/c','timeout','/t','86400'` or a tiny service; check
   `(Get-Process).Count` after starting them).
5. **G3 storm, preliminary (12 min of ≥ 30):** on `dc` (no IIS, no ASP.NET; `.NET CLR Memory` exists) with G3 forced
   at 1 s: Diagnosis-PLA/Operational logged 9 events, **all in the start minute** (6 × ID 1010 Error, plus 1000/1001/1003);
   none afterwards. Application/System showed only service noise (SCM 7036/7040) still to be compared with the
   baseline window 09:43:25–09:53:25Z.
6. Drive (`files/`) refuses concurrent writes from two processes ("Resource deadlock avoided"): write lab logs
   locally, copy to Drive at milestones.
7. `az` defaults to another subscription than the lab: run `direnv exec . sh -c 'az account set --subscription
   "$AZURE_SUBSCRIPTION_ID"'` once (R15 applies: never print it). azd has its own login (template form in the lab's
   HANDOVER). `azd init` ran `git add` in this repo; R14's scrub rule now refuses `.lab/`.

## RUNNING on lab18 (left on purpose; P16 measurement may keep running)

Lab: `rg-lab18` (sub VezirLabs), VMs `dc` and `vm1` (the template's web member; its real VM name is in
`files/private-refs.md`, it is on the denylist, use `vm1` in the record) (Standard_B2s_v2, the template default; `vmSize` is not settable
through azd), template v1.4.1, azd project in `.lab/perfmon-blackbox/` (gitignored), env `lab18`. Registered UP in
the private lab template's lab register (`files/private-refs.md` has its path). ~21 $/day.

| VM | Set | What | Started (UTC) | Output |
|---|---|---|---|---|
| vm1 | `BbWrap1` | 36 counters, 1 s, circular 512 MB | 2026-10-11 10:05 | `C:\ProgramData\PerfmonBlackbox\blg-BbWrap1\PerfmonBlackbox.blg` |
| vm1 | `BbWrap2` | identical twin of BbWrap1 (wrap proof: stop the two ≥ 30 min apart) | 10:05 | `…\blg-BbWrap2\…` |
| vm1 | `BbFull10` | full 56 counters, **10 s** (P19 default), 512 MB | 10:05 | `…\blg-BbFull10\…` |
| dc | `BbStorm` | full 56 with **G3 forced** on a no-IIS box, 1 s, 512 MB | 09:53:25 | `…\blg-BbStorm\…` |

All four are PLA collectors running as SYSTEM; they survive logoff, not a reboot. The Mac-side driver is **stopped**.

**How to read / finish (from the repo root, `v() { (cd .lab/perfmon-blackbox && direnv exec ../.. scripts/vmssh "$@"); }` (for `vm1` pass the real VM name from `files/private-refs.md`),
`PS='powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\PerfmonBlackbox\measure-buffer.ps1'`):**
- Size while running: `v vm1 "$PS -Action sample -SetName BbWrap1"` (bytes; reaching ~536,870,912 = full).
- **Wrap proof (c):** at 1 s the 36-set fills in ≈ 2.85 h (≈ 12:55 UTC). After it is full, stop `BbWrap1` with
  `v vm1 "$PS -Action readback -SetName BbWrap1"` (prints bytes, samples, first and last sample), wait ≥ 30 min, then
  the same for `BbWrap2`. Pass: both sizes at the max, first sample later than 10:05 (oldest gone), BbWrap2's first
  sample later than BbWrap1's (oldest moves forward), last sample ≈ stop time (newest present). True time to 512 MB =
  first-full time from the size polls (or samples × interval).
- **BbFull10:** after ≥ 22 h it should be full; readback gives the real 10 s hours for the full set.
- **Storm (P18):** `v dc "$PS -Action events -Since 2026-10-11T09:53:25Z"` (per log/provider/id/level) and the same
  with `-Since 2026-10-11T09:43:25Z` minus the run for the baseline; per minute: group `Get-WinEvent` by
  `TimeCreated` minute (command in `files/lab-log/261011-lab18-local/261011-lab18.md`). Then
  `v dc "$PS -Action readback -SetName BbStorm"` and `-Action recorded` (proves the other counters were recorded).
- **Stop everything:** `v vm1 "$PS -Action stop -SetName BbWrap1; $PS -Action stop -SetName BbWrap2; $PS -Action stop -SetName BbFull10"`,
  `v dc "$PS -Action stop -SetName BbStorm"`.
- Logs and partial results: `files/lab-log/261011-lab18-local/` (CSV `261011-lab18-measure.csv`, `261011-lab18.md`
  timeline, `measure-driver.sh` = the Mac driver).
- Lab teardown when done (and register update in the same commit): `cd .lab/perfmon-blackbox && direnv exec ../..
  azd down --purge --force`, then lab-audit in the template repo. arc1 is added after PLAN-OK (now given).

## Implementation order I would take

1. **Finish P16/P18 measurements** (above), then put measured hours, the formula and the storm answer in
   `decisions.md`; confirm or change `ExportEveryHours` = 4 for Emre.
2. **Local, no Azure, CI first:** synthetic fixtures + L01–L07 (converter, perfq, masker, fetch-latest selection,
   export window/hole logic in Pester on a Windows runner, template check). Add CI jobs (Windows runner for Pester and
   the package build).
3. **Package:** `PerfmonBlackboxDsc` class resources R1–R6, `Start-PerfmonBlackbox.ps1` (pending-buffer path),
   `Export-PerfmonBlackbox.ps1` (stop/move/start roll per lab fact 1, relog window, holes, manifest, IMDS/HIMDS token,
   PUT Blob), G3 auto-detect; `build.ps1`; T01 on the Windows runner.
4. **Infra** (`infra/main.bicep`): storage (private endpoint, no shared key), container, lifecycle 30 d, custom
   write-only role, agent reader role. T13, T14.
5. **Policies** (`policy/build-policies.ps1`): split `-vm` / `-arc`, parameters (MaxSizeMB, SampleIntervalSeconds,
   ExportEveryHours, StorageAccountName, ContainerName, LocalKeepMB), DINE nested role assignment with the ABAC
   condition. T02, T03.
6. **Lab:** add `arc1` (Learn "Evaluate Arc on an Azure VM"; stop condition P10 if it cannot be done), assign both
   policies, run T04–T12 on `vm1` and `arc1`, including T06b–T06f, T07b, T10–T10c.
7. **Skill v2.1:** `Processor Information` support, `perfmon_fetch_latest.py`, manifest gaps in the report; T15, T16 with
   `make-trouble.ps1` and the scorer.
8. README (adopter guide, cost per server), fresh-eyes deploy, tag `perfmon-blackbox/v1.0.0`, release, lab down.

## Waiting on others

- Emre: OPEN-1, OPEN-2 (P8).
- The vezir: the lab service principal secret rotation after the 2026-10-11 print incident (R15); a new secret
  lands in the shared `.env` first, so nothing here breaks.
