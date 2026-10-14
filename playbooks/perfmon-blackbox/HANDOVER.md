# perfmon-blackbox: v1.0.1 B1 fix GREEN on lab20 (Policy view Compliant, 0 redeploys, T18 PASS); release STOPPED: GitHub-mode contentUri question reported to the vezir (2026-10-14).

## Session 6 (2026-10-14, in progress): v1.0.1 lab check (P74)

- 02:10:35Z v1.0.1 storage definition applied (zip/hash unchanged, label 1.0.1); scan 02:10:41–02:18:22Z → the Policy
  view of pbb-vm-storage **Compliant** on dc and vm1 at 02:11:57Z (was NonCompliant: B1 fixed); remediation 1
  (ReEvaluateCompliance) 0 deployments; T18 vm1 storage **PASS** 02:33–02:35Z (`BB_LAB=.lab/lab20`, `T18.sh` directly:
  `run.sh` passes only one argument). Evidence: `.lab/lab20-logs/v101/`.
- **STOP (brief's rule: a doc contradicts a test result):** P70 and the CHANGELOG say "GitHub mode is not affected", but
  GitHub mode's existenceCondition still compares `contentUri`, and lab18 (T18c, 2026-10-12, commit 7db0e9f) recorded
  that the guest assignment GET hides `contentUri` in GitHub mode too. If the policy engine sees it the same way, GitHub
  mode has B1 as well. Never measured (no Policy-view state of pbb-vm was recorded). Reported to the vezir; not fixed.
- AAU 73 vs 35: "first-run setup" **not proven** (see the report to the vezir; traces in `.lab/lab20-logs/v101/aau/`).

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, `CLAUDE.md`, this file, then `decisions.md` (P1–P73; the latest
are P67–P73). Every `az`/`azd` call runs as `direnv exec . <command>` from the repo root.

## Where it stands

- **Released:** v1.0.0 (P66), tag `perfmon-blackbox/v1.0.0`, asset `PerfmonBlackbox.zip` SHA-256
  `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`. Skill perfmon-triage v2.2.
- **v1.0.1 in progress (P70), on `main` after this session, untagged:**
  - **B1 fix** in `policy/build_policies.py`: storage mode's existenceCondition checks
    `guestConfiguration.contentManagedIdentity = system` instead of `contentUri` (Azure returns contentUri = null with a
    managed identity, so the Policy view stayed NonCompliant and every remediation redeployed). GitHub mode unchanged.
    L08 updated; L01 L02 L04 L07 L08 L09 green. **The package zip does not change** (same SHA): only the generated
    definitions do, so v1.0.1 can ship the v1.0.0 zip again (decide at release; P31 checks still apply).
  - **Doc fixes** F1–F5, F7 in `docs/deploy.md` and `docs/parameters.md`; CHANGELOG "Unreleased". Version banners
    ("As of v1.0.0") and the README status are NOT yet bumped: do that in the release commit.
- **lab20 is UP and KEPT** (rg-lab20, dc + vm1, no Arc, built 2026-10-13 16:32–16:59Z from the private lab template;
  register row "kept for v1.0.1"). Template auto-shutdown schedules Disabled (P69); Emre's global automation stops the
  VMs ~21:46Z nightly and moves disks to Standard_LRS (accepted, not restored). Agent cap 1000 AAU.
  Product deployed there by the **fresh-eyes run** (P67): storage mode, `pbb-vm-storage` on the RG (dc and vm1),
  `ExportEveryHours="1"`, storage `stpbb…` (the playbook's), skill perfmon-triage deployed with Author + Standard User.
  Local lab state: `.lab/lab20/` (template clone + azd env), `.lab/lab20-logs/` (raw notes, outputs), `.lab/fresh/`
  (the v1.0.0 clone used for the fresh-eyes run; its `policy/out/` has the v1.0.0 definitions).
- **Blog post 6 part 1** outputs are done (`files/post6-shots/`: A timings + findings, C1–C7, D, D2, S4 fallback; all
  masked). **`files/post6-shots/raw/` is Emre's raw screenshots: never delete or change it.** S2 is skipped (P70) unless
  tomorrow's Policy view is Compliant and Emre wants it.

## What session 5 did (2026-10-13 evening)

P67 second lab today, shared with post 6 → lab20 built (27m39s) → fresh-eyes deploy steps 0–4 (17:01–17:21Z), vm1
Compliant 17:38Z, first zip 18:07Z (`complete`), agent answer 18:10–18:17Z (honest "not hard to use") → P68/P69
shutdown on/off → found **B1** and F1–F7 → P70 (v1.0.1, S2 skipped) → S4 path for Emre (dc/vm1 Bastion + Edge; Emre's
user got Blob Data Reader on `perfmon`) → P71 planted leak + CPU, second question **100/100 PASS** → P72 keep lab20 →
B1 fix + doc fixes committed → P73 vezir decides releases/teardowns for approved work.

## Next (tomorrow, 2026-10-14; the vezir may start the VMs without Emre, P72)

1. Start lab20's VMs (`az vm start -g rg-lab20 -n dc` and the member; the member's real name is in
   `files/private-refs.md` terms: the template's first IIS member). The Boot task taking the old ring into a pending
   piece is expected; the next export reports the off-hours as a gap.
2. Re-create `perfmon-blackbox-vm-storage` with the **current** generator (deploy.md step 2/2b as now written, with
   `--metadata`, version label `1.0.1`), same package container and hash. Then `az policy state trigger-scan -g rg-lab20`
   **before** any remediation (P55); remediate with `--resource-discovery-mode ReEvaluateCompliance`.
3. Check: the guest assignments stay/return Compliant with `assignmentType` ApplyAndAutoCorrect; **the Policy view of
   pbb-vm-storage turns Compliant** for vm1 and dc (that is the B1 test; S2 for Emre if he wants it); a second remediation
   finds nothing to deploy (no needless redeploy); an export uploads (storage mode, T18 on vm1).
4. Green → bring v1.0.1 to the **vezir** (P73): release commit (banners, README status, CHANGELOG section), zip = the
   v1.0.0 asset re-attached unchanged if nothing in the package changed (SHA in decisions first, files scrub-checked,
   P31), tag `perfmon-blackbox/v1.0.1`.
5. Then lab20 teardown on the **vezir's** go (P73), P65 order. Lab-only extras to remove first: dc identity Blob Data
   Contributor on `packages` and Blob Data Reader on `perfmon`; **Emre's user Blob Data Reader on `perfmon`**; lab SP
   SRE Agent Author + Standard User on the agent; gc-prereq + its Contributor; pbb-vm-storage + its 4 role assignments
   (GC Resource Contributor, Reader, Deployer, conditioned RBAC Administrator); the servers' Writer and package Reader
   grants; the agent identities' Reader on `perfmon`; definition `perfmon-blackbox-vm-storage`; the two custom roles;
   then `azd down --purge --force --cwd .lab/lab20`, register DOWN, lab-audit. Also `C:\BbDev\` on vm1 goes with the VM.
6. Later (unchanged): the skill's range mode across a DST fall-back (P63 SKILL-SONRA); RoleAssignmentExists tolerance.

## Open questions

- For Emre (through the vezir): delete the rc pre-releases (all / keep all = current / keep rc.11)? OPEN-1, OPEN-2 (P8).
- The full stage suite on a fresh lab (DoD-1) was not run on lab20 (P67); decide whether v1.0.1's lab check is enough.

## Lab facts that bite

- The first Machine Configuration cycle after a new package only **tests**; the next applies: ~45 min end to end.
- After a definition update, **run a compliance scan before remediating** (P55), or the service re-sync reverts it.
  A guest assignment can turn `Audit` (agent: `custom_inguest`) after a race between the container zip and the
  assignment hash: check `assignmentType`, and a second scan + remediation fixes it (arc1, 2026-10-13).
- A remediation marked Failed can still have written the guest assignment: read the deployment operations.
- `az role assignment list --all --role "<custom name>"` crashes in az 2.89: filter on `roleDefinitionName` in the query.
  JMESPath `starts_with` on scopes is case-sensitive (`resourcegroups` vs `resourceGroups`): compare lower-cased.
- The lab SP cannot read Microsoft Graph: empty principal names do not mean orphans.
- `T01` on dc: wait until no `gc_worker` process is left. T16/T17 start right after a 4-hourly export.
- Masking: pipe lab output through `perl -pe 's/stbb\w+/<account>/g'` and mask GUIDs; never list subscription-wide
  role assignments into evidence (they name other labs). The `ls` alias (eza) breaks on paths: use `/bin/ls`.
- Drive (`files/`) refuses concurrent writes: write locally, copy at milestones.

- lab20: the member VM's real name differs from `vm1` (template naming); mask it in every evidence file. Its storage
  account for the product is the playbook's own `stpbb…`, not the template's `sta…`.
- `ask-agent` (template script) prints `thread <id>` on stderr; the report is the longest agent message.
- Policy evaluation details are only listed with `az policy state list --resource <id> --expand PolicyEvaluationDetails`.

## Standing rules (decisions)

- P73: for approved work the vezir decides lab builds/teardowns and releases; blog publication and OPEN-1/OPEN-2 stay Emre's.
- P31 checks: SHA into decisions.md before publishing; every file of a release zip extracted and scrub-checked first.
- P50–P53: no lab run crosses 21:45Z; never restore disk SKUs; the product never changes a machine's power state.
