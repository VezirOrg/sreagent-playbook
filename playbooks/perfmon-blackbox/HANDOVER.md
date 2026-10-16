# perfmon-blackbox: v1.0.2 is Latest (2026-10-16, same zip, public SHA verified); Drive guide + portal-json on v1.0.2; lab20 teardown handed to the lab template's session.

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, this file, then `decisions.md` (P1–P93; session 9 added P92–P93).
Every `az`/`azd` call runs as `direnv exec . <command>` from the repo root. The owner is the vezir (P73): releases,
teardowns and lab builds for approved work are the vezir's call; ask before anything outward-facing.

## Where it stands (session 9 close, 2026-10-16)

- **Released: v1.0.2 (Latest)**, published by the vezir 2026-10-16 09:07 +03 (06:07Z): tag `perfmon-blackbox/v1.0.2` on
  0a2f0bd, only asset `PerfmonBlackbox.zip`, SHA-256 `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`
  (the v1.0.0/v1.0.1 zip, unchanged; the vezir checked the public download, P31). Only change: default
  `ExportEveryHours` **1** (P90). Skill perfmon-triage v2.2. Notes and zip: `files/perfmon-blackbox/release-v1.0.2/`.
  Earlier: v1.0.0 (P66), v1.0.1 (P86).
- **T22b done (P92):** lab20 started after a ~32 h stop; Compliant on vm1, dc, arc1 and 0 deployments in both
  remediations. **The null `assignmentType` window did not occur** (every sample ApplyAndAutoCorrect), so the P83 null
  branch is still verified by logic only; CHANGELOG and tests.md say so. The vezir counted T22b as a pass.
- **Drive (`files/perfmon-blackbox/`, P93):** `quick-install-v1.0.2.md` (Turkish CLI + portal notes, gaps at its top),
  `portal-json/` (v1.0.2: two storage definitions with placeholders, `definitions-arm.json`, role JSONs, condition,
  README.txt), `skill-v2.2/`, `release-v1.0.2/`. **Superseded but kept:** `quick-install-v1.0.1.md` (banner),
  `portal-json-v1.0.1-SUPERSEDED/`, `release-v1.0.1/`.
- **Portal check (P93):** backend only. Policy Insights summary 2 of 2 and 1 of 1; Resource Graph showed all three
  machines Compliant (06:08Z). The portal blade itself was not viewed: no browser here, and the lab SP cannot sign in.
- **lab20:** still up, VMs **running** (the vezir said not to stop them). Teardown is **handed to the private lab
  template's session** (the vezir, 2026-10-16), not this playbook's next session. Its checklist is below for reference.
- Lab logs of this session: `.lab/lab20-logs/v102/t22b/`, `.lab/lab20-logs/v102/portal/`.

## Next

1. Nothing release-bound is pending. Possible doc work (not started, needs an ask):
   - the minimum Azure CLI version is still undocumented (P87);
   - private DNS zone / VNet link setup is not described in deploy.md;
   - the RBAC Administrator in the definitions' `roleDefinitionIds` is not decided (P88);
   - the bash `az rest` PUT and the guest assignment delete are still marked untested.
2. If a lab is ever built again: measure the null window on purpose (P92). The null seen on 2026-10-14 was on guest
   assignments written by v1.0.0, while the VMs were stopped.
3. lab20 teardown, for whoever does it. P65 order; register DOWN in the private lab template's `docs/labs.md` in the
   same commit; lab-audit. Remove these explicitly first:
   - Emre's user Storage Blob Data Reader on `perfmon`; dc identity Blob Data Contributor on `packages` and Blob Data
     Reader on `perfmon`; the agent identities' Reader on `perfmon`; the lab SP's SRE Agent Author + Standard User.
   - Assignments pbb-vm-storage and pbb-arc-storage, each with its 4 role assignments; gc-prereq and its Contributor.
   - The servers' (dc, vm1, arc1) Writer on `perfmon` and Blob Data Reader on `packages`.
   - Definitions `perfmon-blackbox-vm`, `-vm-storage`, `-arc`, `-arc-storage`; custom roles `PerfMon Blackbox Writer` /
     `Deployer`.
   - Then `azd down --purge --force --cwd .lab/lab20`.

## WAITING (not this playbook's to decide)

- Emre (through the vezir): delete the rc pre-releases (all / keep all = current / keep rc.11)? OPEN-1, OPEN-2 (P8).
- DoD-1: the full stage suite on a fresh lab was not run on lab20 (P67); the vezir decides whether the lab check is enough.
- Root README: the blog part-1 link in the playbook row (optional, a root change; line given to the vezir, P91).
- Later (unchanged): the skill's range mode across a DST fall-back (P63); RoleAssignmentExists tolerance.

## Lab facts that bite

- The first Machine Configuration cycle after a new package only **tests**; the next applies: ~45 min end to end.
- After a definition update, **scan before remediating** (P55). A remediation's scope must be at or below its
  assignment's: `--resource <id>` for a VM-scope assignment, `-g` only for an RG-scope one (P75).
- `assignmentType` can read `Audit` after a mode switch (P80), and was **null** after a nightly stop on v1.0.0-written
  assignments (P83); P83-written ones kept ApplyAndAutoCorrect through a 32 h stop (P92).
- After a VM start, the first agent report comes ~17 min later; arc1 reconnects in ~3 min (P92).
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
- `scripts/scrub-check.sh --msg <file>` scrub-checks any single file (release notes, Drive files).
- Masking: GUIDs, `stpbb…`/`sta…` names, the tenant; the member is `vm1` in every committed file (P84); never list
  subscription-wide role assignments into evidence. `ls` is eza: use `/bin/ls`. A long grep: never cut it with `head`
  before reading it all.
- Drive (`files/`) refuses concurrent writes: write locally, copy at milestones. `files/post6-shots/raw/` is Emre's.

## Standing rules (decisions)

- P73: for approved work the vezir decides lab builds/teardowns and releases; blog publication and OPEN-1/OPEN-2 stay Emre's.
- P31 checks: SHA into decisions.md before publishing; every file of a release zip extracted and scrub-checked first.
- P50–P53: no lab run crosses 21:45Z; never restore disk SKUs; the product never changes a machine's power state.
- P78/P84: own lab machine names may appear (dc, arc1); the web member stays `vm1`.
- P93: `files/perfmon-blackbox/portal-json/` always holds the current release; older sets move to `portal-json-vX.Y.Z-SUPERSEDED/`.
- The customer of P89 is never named, anywhere.
