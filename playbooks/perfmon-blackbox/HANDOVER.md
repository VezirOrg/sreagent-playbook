# perfmon-blackbox: v1.0.1 release commit on main (P86, 2026-10-14, same zip); the vezir tags it; T22b is a post-release check 2026-10-15 morning (fail = v1.0.2).

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, this file, then `decisions.md` (P1–P86; today's are P74–P86).
Every `az`/`azd` call runs as `direnv exec . <command>` from the repo root. The owner is the vezir (P73): releases,
teardowns and lab builds for approved work are the vezir's call; ask before anything outward-facing.

## Where it stands (session 7, 2026-10-14 ~13:00 +03)

- **Released:** v1.0.0 (P66), tag `perfmon-blackbox/v1.0.0`, asset `PerfmonBlackbox.zip` SHA-256
  `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`. Skill perfmon-triage v2.2.
- **v1.0.1 released by P86 ("YAYIN-BUGÜN", Emre via the vezir):** release commit `perfmon-blackbox: release v1.0.1` on
  `main` (stash applied, CHANGELOG `perfmon-blackbox/v1.0.1 (2026-10-14)`). **The vezir** tags `perfmon-blackbox/v1.0.1`
  and creates the GitHub release; notes and the zip for it are in `files/perfmon-blackbox/release-v1.0.1/`. After the
  tag: check the deploy.md asset URL resolves and hashes to 806BCADB…63DD. Generator-only fixes; the package, skill, infra and scripts have no diff since v1.0.0,
  so v1.0.1 ships the **identical zip** (same SHA). In `policy/build_policies.py` the existenceCondition:
  - **B1 (P70, P76):** never reads `contentUri` (Azure returns null in both modes); storage mode checks
    `contentManagedIdentity equals system`, GitHub mode `notEquals system`.
  - **P80 + P83:** `guestConfiguration.assignmentType notIn ["Audit", "ApplyAndMonitor"]`. An assignment the service left
    in Audit is repaired by one remediation; a **null** assignmentType (seen 2026-10-14 02:10Z on dc and vm1 after the
    nightly stop, filled in later by the service) passes, so it causes no redeploy.
  - L08 asserts all of it; L01 L02 L04 L07 L08 L09 green.
- **Lab results 2026-10-14 (lab20; tests.md T20–T22):** T20a–d (Policy view Compliant) and T21a–d (remediation deploys 0)
  green on an Azure VM and on Arc, storage and GitHub mode; T18 vm1 storage, arc1 github and arc1 storage PASS; T22a
  (Audit repaired with one deployment, then 0) green; P83 applied 07:46Z: all Compliant, remediations 0; P83 stability
  closed (21 samples 07:44–09:26Z, two agent reports per machine, no flapping). **T22b (null after the nightly stop) is
  PENDING**: CHANGELOG says "verified by logic, measurement pending".
- **AGENT-ARC (P82) done:** idle question on arc1 (thread d0842b4b…) and the planted run (thread 28b1a3d4…) 95/100 PASS.
  Masked texts and README in `files/post6-shots/agent-arc/`. Blog shots S2-new (final), S3, M1–M4 taken by Emre.
- **P84 (REPO-VM1):** the repo keeps `vm1` for the template's web member; its real name stays on the denylist.
- **P85 closed:** the portal's "0 out of 0" for pbb-arc-storage was the portal scope filter; no playbook change.

## The named stash is spent

"v1.0.1 release edits — apply at release after T22b" (`bbbcac9…`) was applied in the release commit (P86) and dropped
from the shared stash list (found by its message).

## Next (fresh session, 2026-10-15 morning; every lab step ends before 21:45Z)

lab20 is kept running for this (nightly stop as usual).

1. **Start lab20's VMs:** `az vm start -g rg-lab20 -n dc`, the web member (its real name: `files/private-refs.md`; the
   template's first IIS member) and `-n arc1` (the Azure VM that hosts the Arc agent; the Arc machine reconnects by
   itself, check `az connectedmachine show -g rg-lab20 -n arc1 --query status`). Do **not** touch anything else first.
2. **T22b (P83 null check), now a post-release check of v1.0.1 (P86), before any remediation:**
   - Right after the start, record each guest assignment (vm1, dc, arc1: `complianceStatus`, `assignmentType`,
     `lastComplianceStatusChecked`; script pattern in `.lab/lab20-logs/v101/p80/watch2.sh`). A null `assignmentType` here
     is exactly the case under test: note it.
   - `az policy state trigger-scan -g rg-lab20`, then `az policy state list -g rg-lab20` for pbb-vm-storage and
     pbb-arc-storage: **expect all Compliant**.
   - Remediate both with `--resource-discovery-mode ReEvaluateCompliance` (`--policy-assignment <name> -g rg-lab20`):
     **expect 0 deployments** each. Script pattern: `.lab/lab20-logs/v101/p83/run.sh`.
   - Green → T22b row in `docs/tests.md` green (with whether null was actually seen), decisions entry, CHANGELOG v1.0.1
     entry: replace "measurement pending" with what was measured (a doc fix on main, no new release).
   - **If T22b fails** (NonCompliant on a null assignmentType, or a deployment): STOP, write it into decisions and bring
     it to the vezir. The fix ships as **v1.0.2** (P86): the P83 fallback, replace the `notIn` term by two terms,
     `assignmentType notEquals Audit` and `notEquals ApplyAndMonitor` (null passing `notEquals` is measured: P76 GitHub
     mode). Generator only; zip/SHA unchanged; L08 updated; re-create the two storage definitions as in P80/P83 (command
     pattern in decisions P80 "measured"), scan, remediate, expect 0. Then a v1.0.2 release commit; the vezir tags.
3. **Portal check:** Policy → Compliance with the **correct scope** (subscription VezirLabs / rg-lab20; P85): pbb-vm-storage
   2 of 2, pbb-arc-storage 1 of 1, both Compliant.
4. If the vezir has not yet confirmed: the tag `perfmon-blackbox/v1.0.1` exists, its only asset hashes to 806BCADB…63DD,
   and the deploy.md asset URL resolves.
5. **lab20 teardown** on the vezir's GO (P73), P65 order, then register DOWN in the private lab template's `docs/labs.md`
   (same commit as the teardown) and lab-audit. Remove explicitly first:
   - **Emre's user Blob Data Reader on `perfmon`** (lab-scoped), dc identity Blob Data Contributor on `packages` and Blob
     Data Reader on `perfmon`, the agent identities' Reader on `perfmon`, lab SP SRE Agent Author + Standard User on
     the agent.
   - Assignments pbb-vm-storage and pbb-arc-storage, each with its 4 role assignments (GC Resource Contributor, Reader,
     Deployer, conditioned RBAC Administrator); gc-prereq + its Contributor; stale state rows of the deleted pbb-arc /
     pbb-vm need nothing.
   - The servers' (dc, vm1, arc1) Writer grant on `perfmon` and Blob Data Reader on `packages`.
   - Definitions `perfmon-blackbox-vm`, `-vm-storage`, `-arc`, `-arc-storage` (subscription scope); custom roles
     `PerfMon Blackbox Writer` / `Deployer`.
   - Then `azd down --purge --force --cwd .lab/lab20` (the RG takes the Arc machine resource `arc1`, the arc1 VM, NICs,
     disks, storage, `C:\BbDev\` on the VMs). Register row DOWN; lab-audit.

## WAITING (not this playbook's to decide)

- Emre (through the vezir): delete the rc pre-releases (all / keep all = current / keep rc.11)? OPEN-1, OPEN-2 (P8).
- DoD-1: the full stage suite on a fresh lab was not run on lab20 (P67); the vezir decides whether v1.0.1's lab check
  is enough.
- Later (unchanged): the skill's range mode across a DST fall-back (P63 SKILL-SONRA); RoleAssignmentExists tolerance.

## Lab facts that bite

- The first Machine Configuration cycle after a new package only **tests**; the next applies: ~45 min end to end.
- After a definition update, **scan before remediating** (P55). A remediation's scope must be at or below its
  assignment's: `--resource <id>` for a VM-scope assignment, `-g` only for an RG-scope one (P75).
- `assignmentType` can read `Audit` after a mode switch (P80) and **null** after the nightly stop (P83); check it.
- The guest assignment GET's `lastComplianceStatusChecked` moves only with an agent report (roughly every 15–60 min).
- A remediation marked Failed can still have written the guest assignment: read the deployment operations.
- Portal Policy → Compliance: check the **scope** selection before trusting a count (P85).
- `tests/run.sh` passes only one argument: run `T18.sh <vm1|arc1> <storage|github>` directly with `BB_LAB=$PWD/.lab/lab20`.
- `tests/lab/common.sh` resolves its guest scripts from `$0`: source it only from a script in `tests/lab/` (under
  `sh -c` the `guest` helper silently does nothing). arc1 needs `--user $VM_ADMIN_USERNAME` (not domain-joined).
- `ask-agent` runs from inside `.lab/lab20` but under the **repo root's** direnv (`direnv exec . bash -c "cd .lab/lab20 &&
  scripts/ask-agent …"`); `direnv exec .` inside `.lab/lab20` has no az login. It prints `thread <id>` on stderr; the
  report is the longest agent message.
- Background logs through `grep` buffer: write watcher output straight to the file.
- The product storage account is private-endpoint only: list blobs from inside a VM, not from the laptop.
- `az role assignment list --all --role "<custom name>"` crashes in az 2.89: filter on `roleDefinitionName`. JMESPath
  `starts_with` on scopes is case-sensitive.
- The lab SP cannot read Microsoft Graph: empty principal names do not mean orphans.
- Masking: GUIDs, `stpbb…`/`sta…` names, the tenant; the member's real name is `vm1` in every committed file (P84);
  never list subscription-wide role assignments into evidence. `ls` is eza: use `/bin/ls`.
- Drive (`files/`) refuses concurrent writes: write locally, copy at milestones. `files/post6-shots/raw/` is Emre's: never
  change it.

## Standing rules (decisions)

- P73: for approved work the vezir decides lab builds/teardowns and releases; blog publication and OPEN-1/OPEN-2 stay Emre's.
- P31 checks: SHA into decisions.md before publishing; every file of a release zip extracted and scrub-checked first.
- P50–P53: no lab run crosses 21:45Z; never restore disk SKUs; the product never changes a machine's power state.
- P78/P84: own lab machine names may appear (dc, arc1); the web member stays `vm1`.
