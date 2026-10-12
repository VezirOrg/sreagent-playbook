# perfmon-blackbox: session 3 OPEN (2026-10-12). Lab18 UP; rc.8 on both; T18b, T10d, T18c, T18f green; T16 run 5 arc1 = 100; T07b arc1 green (computed); RING-A in code (rc.9 build pending); T18d/e running on arc1.

## Session 3 (2026-10-12, in progress)

- **11:45Z Emre (via the vezir): T18D-ARC1, RING-A, T07B-HESAP** (P54 decided, P56). T07b arc1 **green, computed**
  (26.4 h). RING-A code + L05 39/0 committed (23c88ac); rc.9 not yet built: T01 on dc blocked by dc's own GC agent
  running a baseline ("Failed to initialize DSC library" while its gc_worker runs); T10e (vm1's real unreadable ring)
  after rc.9 is on vm1. T18d on arc1 in progress (`T18de.sh`: reader role removed 12:29Z, unchanged re-PUT 12:30:49Z);
  **after T18d/e: `T18de.sh restore`, then `T18.sh arc1 storage` must pass.** T16 vm1 run 5 in progress (load 12:24Z).
- Lab18 restarted 05:15Z (P50), healthy: T06, T04 green on vm1 and arc1. **T18b GREEN** 07:19Z: first-party PUT 07:01Z
  → Compliant 07:05Z, still storage + system identity (P48 confirmed). LOCK-A (P49) in the code, L05 37/0. Next: rc.8.
- **rc.8 published** (SHA in P46; release perfmon-blackbox/v1.0.0-rc.8, pkg version 1.0.7). vm1 on rc.8 08:14Z (the first
  cycle after a new package only tests, the next applies: ~45 min end to end). **T10d GREEN** on vm1 (first run).
- arc1 storage-mode update: the first try was rolled back by a service re-sync; after a compliance scan + remediation
  arc1 downloaded rc.8 (08:36:58Z) and kept it across the next service PUT (08:43:59Z). **P55**: scan before remediating
  (operations.md, lab-policy.sh). **Both machines on rc.8.**
- vm1 keeps an unreadable pending ring (`20261011-191221-00-boot.blg`, cut by an abrupt restart 10-11 19:12Z) forever and
  warns on every export; the ~10 min loss was labelled as a gap. Design question reported (give up after N runs?).
- **T18c GREEN** (vm1 storage and back, no flapping). Test fixes: T18 judges only the last download attempt; its GitHub
  check no longer needs `contentUri` (ARM hides it). deploy.md: the 403 window when switching to storage mode.
- **P52 (Emre, KAPANIS-19):** lab18's 19:00Z template auto-shutdown (dc, vm1) is DISABLED until v1.0.0. The lab day
  ends at ~21:46Z. **CHECKLIST: re-enable both schedules at v1.0.0 or when the playbook work stops (command in P52).**
- **P51 (Emre, KABUL):** the nightly stop (~21:46Z) and disk downgrade stay. No lab run crosses 21:45Z (the 19:00Z
  auto-shutdown of dc and vm1 comes first); restart after a nightly stop is pre-approved (dc, vm1, arc1); never restore
  disk SKUs again; mark disk-latency findings as an HDD lab artefact.
- Opened clean (no stray commits). Local L01–L09 green. **P50:** Emre allowed the restart (08:13); in progress: disk SKUs
  restored while deallocated, then dc → vm1 → arc1 started and checked. The caller is Emre's nightly lab automation
  (~21:46Z): no lab run across 21:45Z without telling the vezir; if it stops the lab again, do not restart, report.
- **T10d** (P46 lab test) scripted: `tests/lab/T10d.sh` (block by name, start the export, unblock after 3 min, pass =
  "uploaded on attempt 2", task result 0, continuous zip). `guest/export-now.ps1` gained `-MaxWaitSeconds`/`-StartOnly`;
  **T10c** now waits up to 30 min (since rc.8 a blocked run fails only after its +5/+15-min retries). Syntax-checked
  only (no pwsh on the Mac; first run = next lab use).
- Docs: operations.md named a log that does not exist (`export.log` → `log\perfmonblackbox.log`; the event log gets
  only the final failure); tests.md status refreshed (T18b partial, T10d row, R1 note superseded by P46); test-plan T10d.
- **Open (to the owner):** P46 holds the machine-wide lock (`Lock-Bb`) through the retry sleeps (up to ~15 min); a
  DSC `Set` of `[BlackboxCollector]` (parameter change) in that time waits up to 10 min for the lock and then fails
  (retried at the next 15-min check). No data loss; see the owner report for the options.


## Close of session 2 (2026-10-11)

**lab18 VMs stopped 21:45Z by Emre's own lab-management automation (identified 2026-10-12, P50; it runs nightly at ~21:46Z and downgrades disks). Restarted 2026-10-12 05:15Z under P50.**
(dc, vm1, arc1 deallocated at 21:45:26Z in one second by Emre's lab-management automation, P50.)

- **Resume recipe (once the owner allows the lab up)**, all from the repo root, every az call via `direnv exec .`:
  1. Start dc, vm1, arc1 (`az vm start -g <lab rg> -n <name>`; dc first, DNS). Wait until `v arc1 hostname` answers.
  2. **T18b (decides P48):** state left behind: assignments `pbb-vm` (GitHub) and `pbb-arc-storage`; arc1 holds Reader
     on `packages` and Writer on `perfmon`. Watch the arc1 agent log
     (`C:\ProgramData\GuestConfig\arc_policy_logs\gc_agent.log`, every 10 min a pull) and the activity log for
     PUTs on arc1's guest assignment. Pass = every pull says `from private blob using managed identity` with no
     `Managed identity not provided`, **including the first pull after a first-party service PUT** (the 21:07 pattern;
     21:38:33 was the last one seen, its following pull never ran), over at least two pulls; then
     `direnv exec . sh playbooks/perfmon-blackbox/tests/lab/T18.sh arc1 storage` (call T18.sh directly: run.sh passes
     only the machine). `tests/lab/watch-gc.sh arc1 60` prints both (new script, syntax-checked, not yet run against the lab; its prototype was).
     Fail (a flip back to GitHub) = stop and report to the owner.
  3. **rc.8 (P46, P31 standing permission):** `tests/run.sh T01 dc` (build + compliance on dc) → unpack the built zip
     into an empty dir and `scripts/scrub-check.sh` every file → write the SHA-256 into decisions.md under P46
     (`- **rc.8** …`, like rc.7) and **commit that first** → `gh release create perfmon-blackbox/v1.0.0-rc.8`
     (prerelease, not latest, the zip as the only asset, notes "Lab test build, not for use") → update the lab-only
     `pbb-package.env` (PKG_URI, PKG_SHA256, PKG_VERSION) → report URL + SHA to the owner.
  4. **Roll rc.8 out:** vm1 via `lab-params.sh` (GitHub mode, as now). arc1 stays in storage mode: first
     `lab-package.sh` (copies the release zip unchanged into `packages`, hash checked), then
     `lab-params.sh machine=arc1 PackageContainerResourceId=<packages container ID>`.
  5. **P46 lab test (vm1):** `direnv exec . sh playbooks/perfmon-blackbox/tests/run.sh T10d vm1` (session 3; it
     blocks the storage name, starts an export, unblocks after ~3 min; pass = `log\perfmonblackbox.log` shows
     `upload attempt 1 failed … retry in 300 s`, then `uploaded on attempt 2`, task result 0, zip continuous).
     Record in tests.md and tell the owner (and the v1.0.0 estimate impact).
  6. Then T18c (vm1 storage and back, by the P48 switch procedure, watch for flapping), T18d/e/f, T16 run 5, T17.

## Session 2 summary

- Decisions P20–P48; root R16–R19. Docs analysis-first (P35, P38); tests.md with live statuses.
- **Green:** L01–L09 (+ CI Windows job; L02 now also covers range mode end to end); T01, T02, T03, T13, T14; **vm1:**
  T04–T07, T07b, T08, T09–T12, T10c, T15, **T16 run 4 = 100** under P43 (plants verified in the capture, P42);
  **arc1:** T04–T07, T06b–T06e, T09–T12, T10b, T15. Wrap proven, storm none, formula P27. Resilience R1 (real DNS
  outage, no data lost).
- **Lab pre-releases (P29/P31):** rc.1 … rc.7 published; rc.7 runs on vm1 and arc1. **P46** (export retries +5/+15 min
  in the same run, Export task restart-on-failure backstop, operations.md outage section) committed 7edede7, L05 green
  (Pester 35/0, lint 0); **rc.8 not built** (recipe step 3).
- **Package from storage (P45 → P47 → P48):** system-identity download PROVEN on Arc (arc1 agent log 21:00:40Z, again
  21:20:45Z and 21:35:48Z: "from private blob using managed identity", downloaded, validated, applied). No SAS anywhere.
  Our defects found on the way: P47 (assignment API 2022-01-25 dropped `contentManagedIdentity` → 2024-04-05; `az role
  assignment create` does not update a stale delegation condition → lab-policy updates it in place, deploy.md warns),
  **P48** (the service re-syncs the guest assignment from the definition metadata, so the package source is fixed at
  generation: `perfmon-blackbox-<kind>-storage` definitions; accepted by the vezir with three conditions). Written up for
  Emre's blog in docs/architecture.md ("Why the package source is fixed when the definitions are generated").
  T18b timeline after the switch: 21:20:45 storage download, 21:22:52 service PUT, 21:25:47 Compliant, 21:34:03 our
  remediation (writer + reader OK), 21:35:48 storage download, 21:38:33 service PUT, 21:40:50 Compliant; the deciding
  pull (~21:45:50) never ran (lab stopped).
- **Lab state left behind:** policy assignments `pbb-vm` (GitHub, rc.7) and `pbb-arc-storage` (storage, rc.7 in
  `packages`), prerequisites `pbb-gc-prereq`; `pbb-arc` removed by the P48 switch (with its identity's role
  assignments). All three VMs deallocated.
- **Done while the lab was down:** naming pass ("Azure Machine Configuration" in prose, note in architecture.md;
  7f5c38a); L02 range-mode test (6b058d2); stray temp script removed.
- **Next after the recipe:** (done: T18c, T18f, T16 run 5 arc1 = 100 at 11:34Z) T18d/e (owner to choose arc1 or vm1) → T16 run 5 vm1 → T17 → T08/T07b arc1 → T06f
  part 2 → least-privilege agent role (P30) → docs pass → fresh-eyes deploy → **re-enable lab18 auto-shutdown (P52)**; v1.0.0 = Emre's gate.
- Lab extras (register row updated): arc1; vm1 data disk + patchMode; dc identity = lab verifier; lab SP agent admin
  (P30, remove at teardown). Lab auto-shutdown 19:00Z (dc and vm1) DISABLED until v1.0.0 (P52, re-enable checklist); restart after the nightly stop is pre-approved (P51). Skill v2.1 backup
  in `files/` (path in the owner report).

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
