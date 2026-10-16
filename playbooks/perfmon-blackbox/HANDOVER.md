# perfmon-blackbox: T22b green 2026-10-16 (null not reproduced, P92); v1.0.2 release commit on main, awaiting the vezir's tag; lab20 still up.

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, this file, then `decisions.md` (P1–P91; session 8 added P87–P91).
Every `az`/`azd` call runs as `direnv exec . <command>` from the repo root. The owner is the vezir (P73): releases,
teardowns and lab builds for approved work are the vezir's call; ask before anything outward-facing.

## Session 9 (2026-10-16, opened by the vezir: "BAŞLA")

- **T22b done (P92):** lab20 VMs started 05:24:46Z after a ~32 h stop; guest assignments Compliant/ApplyAndAutoCorrect
  before and after the start, **never null** (samples every minute 05:24–06:04Z); scan 05:43–05:51Z all three
  Compliant; remediations pbb-vm-storage 0 and pbb-arc-storage 0 (06:05Z). Null branch stays verified by logic only.
  Logs: `.lab/lab20-logs/v102/t22b/`.
- **v1.0.2 release commit** (CHANGELOG dated 2026-10-16, README/deploy.md/banners to v1.0.2, tests.md T22b row);
  local L01–L04, L06–L09 green. Notes and the (unchanged) zip: `files/perfmon-blackbox/release-v1.0.2/`. The vezir tags
  `perfmon-blackbox/v1.0.2` and publishes (P73), then checks the public asset SHA (P31).
- **Not done (not asked this session):** portal-json regen for v1.0.2 (Next 4), portal check (Next 5), lab20 teardown
  (Next 6, a separate step on the vezir's GO). lab20 VMs are **running**; nightly auto-shutdown stops them.

## Where it stands before session 9 (session 8 close, 2026-10-15)

- **Released:** v1.0.0 (P66) and **v1.0.1 (P86, Latest)**: tag `perfmon-blackbox/v1.0.1` on 63040d9, only asset
  `PerfmonBlackbox.zip`, SHA-256 `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD` (the v1.0.0 zip,
  unchanged). Skill perfmon-triage v2.2. Notes and zip: `files/perfmon-blackbox/release-v1.0.1/`.
- **On main, unreleased (CHANGELOG "Unreleased: perfmon-blackbox/v1.0.2"):** P90 default `ExportEveryHours` **1** (was 4)
  in `policy/build_policies.py`, docs, tests (L-tests 38 OK), both flow SVGs (EN, TR). **PAKET-AYNI (Emre):** v1.0.2
  reuses the v1.0.1 zip unchanged (same SHA, same `contentHash`); the package's fallback `'4'` (config.ps1, DSC class,
  `New-BbTaskXml`) stays, it never applies because every definition passes all six parameters. Existing installs: an
  explicit value keeps its parameterHash; an assignment on the default moves to 1 at its next remediation after the
  definitions are updated (P90).
- **P89 docs (on main, no release):** deploy.md prerequisites (rights that work: definitions need Owner or Resource
  Policy Contributor at subscription scope), **1b** existing storage account (containers `perfmon` + `packages`, custom
  roles as portal JSON), **3b** portal route (definitions by REST PUT; the portal's own unconditioned RBAC Administrator
  grant to delete; PIM Active/Permanent), Compliant within ~1 h, first event is 1002; operations.md event table and full
  Remove (guest assignment delete **untested**); cost.md SRE Agent Unit from the Retail Prices API; Learn's
  Administrator note for skills next to our tested Author + Standard User.
- **First install outside the lab (P89):** 3 Azure VMs, existing private-endpoint storage, portal + Cloud Shell, done
  live by the vezir with Emre; definitions by `Invoke-AzRestMethod` PUT (201, metadata verified); collector Running,
  `ExportEveryHours` 1 explicit. Its skill side (existing SRE Agent) was briefed: files in
  `files/perfmon-blackbox/skill-v2.2/`; the agent needs VNet integration that reaches the private endpoint.
- **P91:** the playbook README links blog part 1 (EN, TR). The root README row was not changed (a root change; the exact
  line was given to the vezir).
- **Drive (`files/perfmon-blackbox/`):** `quick-install-v1.0.1.md` (P87, Turkish CLI guide), `portal-json/` (v1.0.1
  storage-mode definitions with placeholders, `definitions-arm.json`, role JSONs, RBAC condition), `skill-v2.2/`. The
  dropped portal guide was deleted (the vezir's word).
- **lab20** still runs (nightly stop): T20–T22a green on 2026-10-14; **T22b pending**.

## Next (2026-10-15; every lab step ends before 21:45Z)

1. **Start lab20's VMs:** `az vm start -g rg-lab20 -n dc`, the web member (real name: `files/private-refs.md`) and
   `-n arc1`; check `az connectedmachine show -g rg-lab20 -n arc1 --query status`. Touch nothing else first.
2. **T22b (P83 null check, post-release check of v1.0.1), before any remediation:**
   - Right after the start, record each guest assignment (vm1, dc, arc1: `complianceStatus`, `assignmentType`,
     `lastComplianceStatusChecked`; pattern `.lab/lab20-logs/v101/p80/watch2.sh`). Note whether `assignmentType` is null.
   - `az policy state trigger-scan -g rg-lab20`, then `az policy state list -g rg-lab20` for pbb-vm-storage and
     pbb-arc-storage: **expect all Compliant**.
   - Remediate both with `--resource-discovery-mode ReEvaluateCompliance`: **expect 0 deployments** (pattern
     `.lab/lab20-logs/v101/p83/run.sh`).
   - Green → T22b row in `docs/tests.md`, a decisions entry, CHANGELOG v1.0.1 "measurement pending" replaced by the
     measurement.
   - **Fail** (NonCompliant on null, or a deployment): STOP, decisions entry, to the vezir. The fix joins v1.0.2: replace
     the P83 `notIn` term by `assignmentType notEquals Audit` and `notEquals ApplyAndMonitor`; generator only, zip/SHA
     unchanged, L08 updated; re-create the two storage definitions (P80 "measured"), scan, remediate, expect 0.
3. **v1.0.2 cut** (after T22b): default `ExportEveryHours` 1 (+ the T22b fix if it failed); **same zip** as v1.0.1
   (P90, PAKET-AYNI: SHA `806BCADB…63DD`). Release commit: CHANGELOG heading dated, deploy.md table and clone tag to
   v1.0.2, `--version 1.0.2`; release notes scrub-checked; the vezir tags and publishes (P73), then the public asset SHA
   is checked. Upgrade note for adopters: an assignment on the default moves to 1; pass `"4"` to keep 4.
4. **Regenerate `files/perfmon-blackbox/portal-json/` for v1.0.2** (Drive, not the repo): the two storage definitions with
   `--version 1.0.2`, the same SHA and the placeholder container ID, and `definitions-arm.json` (expressions escaped
   `[[`, check 0 unescaped); role JSONs and the condition file are unchanged. Scrub-check each file.
5. **Portal check:** Policy → Compliance with the correct scope (P85): pbb-vm-storage 2 of 2, pbb-arc-storage 1 of 1.
6. **lab20 teardown** (after T22b, on the vezir's GO, P73), P65 order; register DOWN in the private lab template's
   `docs/labs.md` in the same commit; lab-audit. Remove explicitly first:
   - **Emre's user Storage Blob Data Reader on `perfmon`** (lab-scoped); dc identity Blob Data Contributor on `packages`
     and Blob Data Reader on `perfmon`; the agent identities' Reader on `perfmon`; the lab SP's SRE Agent Author +
     Standard User on the agent.
   - Assignments pbb-vm-storage and pbb-arc-storage, each with its 4 role assignments (GC Resource Contributor, Reader,
     Deployer, conditioned RBAC Administrator); gc-prereq + its Contributor.
   - The servers' (dc, vm1, arc1) Writer grant on `perfmon` and Blob Data Reader on `packages`.
   - Definitions `perfmon-blackbox-vm`, `-vm-storage`, `-arc`, `-arc-storage`; custom roles `PerfMon Blackbox Writer` /
     `Deployer`.
   - Then `azd down --purge --force --cwd .lab/lab20`. Register row DOWN; lab-audit.

## Later doc work (not started)

- Minimum Azure CLI version (the lab ran 2.89) is still undocumented (P87).
- The portal's unconditioned RBAC Administrator grant: documented (3b); dropping RBAC Administrator from the
  definitions' `roleDefinitionIds` is not decided (P88).
- The bash `az rest` PUT for definitions and the guest assignment delete in operations.md are marked untested.

## WAITING (not this playbook's to decide)

- Emre (through the vezir): delete the rc pre-releases (all / keep all = current / keep rc.11)? OPEN-1, OPEN-2 (P8).
- DoD-1: the full stage suite on a fresh lab was not run on lab20 (P67); the vezir decides whether the lab check is enough.
- Root README: the blog part-1 link in the playbook row (optional, a root change; line given to the vezir, P91).
- Later (unchanged): the skill's range mode across a DST fall-back (P63); RoleAssignmentExists tolerance.

## Lab facts that bite

- The first Machine Configuration cycle after a new package only **tests**; the next applies: ~45 min end to end.
- After a definition update, **scan before remediating** (P55). A remediation's scope must be at or below its
  assignment's: `--resource <id>` for a VM-scope assignment, `-g` only for an RG-scope one (P75).
- `assignmentType` can read `Audit` after a mode switch (P80) and **null** after the nightly stop (P83); check it.
- `lastComplianceStatusChecked` moves only with an agent report (roughly every 15–60 min).
- A remediation marked Failed can still have written the guest assignment: read the deployment operations.
- Portal Policy → Compliance: check the **scope** selection before trusting a count (P85).
- `tests/run.sh` passes only one argument: run `T18.sh <vm1|arc1> <storage|github>` directly with `BB_LAB=$PWD/.lab/lab20`.
- `tests/lab/common.sh` resolves its guest scripts from `$0`: source it only from a script in `tests/lab/`. arc1 needs
  `--user $VM_ADMIN_USERNAME` (not domain-joined).
- `ask-agent` runs under the **repo root's** direnv (`direnv exec . bash -c "cd .lab/lab20 && scripts/ask-agent …"`);
  thread ID on stderr; the report is the longest agent message.
- Background logs through `grep` buffer: write watcher output straight to the file.
- The product storage account is private-endpoint only: list blobs from inside a VM, not from the laptop.
- `az role assignment list --all --role "<custom name>"` crashes in az 2.89: filter on `roleDefinitionName`. JMESPath
  `starts_with` on scopes is case-sensitive.
- The lab SP cannot read Microsoft Graph: empty principal names do not mean orphans.
- Masking: GUIDs, `stpbb…`/`sta…` names, the tenant; the member is `vm1` in every committed file (P84); never list
  subscription-wide role assignments into evidence. `ls` is eza: use `/bin/ls`. A long grep: never cut it with `head`
  before reading it all (session 8 missed the TR SVG that way).
- Drive (`files/`) refuses concurrent writes: write locally, copy at milestones. `files/post6-shots/raw/` is Emre's.

## Standing rules (decisions)

- P73: for approved work the vezir decides lab builds/teardowns and releases; blog publication and OPEN-1/OPEN-2 stay Emre's.
- P31 checks: SHA into decisions.md before publishing; every file of a release zip extracted and scrub-checked first.
- P50–P53: no lab run crosses 21:45Z; never restore disk SKUs; the product never changes a machine's power state.
- P78/P84: own lab machine names may appear (dc, arc1); the web member stays `vm1`.
- The customer of P89 is never named, anywhere.
