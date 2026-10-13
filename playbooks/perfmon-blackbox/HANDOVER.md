# perfmon-blackbox: session 4 OPEN (2026-10-13): rc.11 GREEN on vm1 + arc1; lab18 TORN DOWN 15:32Z (P65, audit CLEAN); next: v1.0.0 release (Emre GO).

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, `CLAUDE.md`, this file, then `decisions.md` (P1–P59; the
latest are P50–P59) and **`docs/second-lab-plan.md`**. Every `az`/`azd` call runs as `direnv exec . <command>` from
the repo root. Lab scripts: `tests/run.sh <ID> [vm1|arc1]` or `sh tests/lab/<ID>.sh <machine> [step]` (call a lab
script **from its own directory or via its repo path**: `common.sh` resolves the lab from `$0`, so a wrapper script
elsewhere breaks it).

## Session 4 (2026-10-13), in progress

- **rc.11 green on both** (tests.md "rc.11 on lab18"). arc1 needed a second P55 remediation: its assignment had turned
  Audit; the arc remediations fail on `RoleAssignmentExists` (the hand-restored package reader, P56): a post-v1.0.0
  follow-up. T06f part 2 green (T06f.sh now waits for the next Machine Configuration run).
- End-to-end flow diagram `docs/img/perfmon-blackbox-flow.svg` (+ Turkish `.tr.svg`, corrected); SKILL-SONRA in P63.
- lab18 torn down (P65): 15:32Z, register DOWN, lab-audit CLEAN. No lab is up for this playbook until the second lab (10-14).
- Emre GO for v1.0.0 (after the teardown).
- P60 CAP-1000 (second lab agent cap 1000 AAU/month), P61 KALSIN (skill stays on `deploy-skill.sh`).
- lab18 restarted 04:56Z (nightly stop was in window); T04/T06 green on both.
- **T08 arc1 red on rc.9** (05:00Z): clean restart, but PLA did not stop the collector after a long Windows Update
  preshutdown; the ring stayed unclosed and unreadable (research + salvage in `docs/tests.md`; no variant reads it;
  multi-input relog fails as a whole on one bad file).
- **T08-FIX (Emre): P62, rc.10** = Roll task every 15 min (R7), R6 on LocalKeepMB, machine_off from recorded boots,
  unreadable span from the recorded ring start, tiny pieces (<2 samples) deleted. L05 47/47, T01 green, rc.10 published
  (SHA in P62), on origin/main 44bb214. `.lab/perfmon-blackbox/pbb-package.env` = rc.10 (`.rc9` backup).
- Adopter docs: operations.md "How it works on the server" (purpose and reason per step), contradictions a)–d) fixed.
- rc.10 on lab18: T04, T07, T08 green on both (T08 fixed). P30 trial PASS: Author + Standard User suffice (P64);
  Administrator stays removed. Emre: RELOG-RC11 + gate DST = DST-A → **rc.11** (P63, SHA there), on origin/main 4ce0490;
  `pbb-package.env` = rc.11 (`.rc10`, `.rc9` backups). Side tests on dc (multi-input relog, tiny pieces, DST simulation)
  are in `docs/tests.md` with evidence in `files/test-runs/261013-lab18/`.
- Next today (old line kept for reference): rc.10 rollout → T04, T06, T07, T08, T09, T10, T11, T19 on both, T07b arc1, one T15 → T06f part 2 (arc1)
  → P30 → live teardown list to the vezir (nothing deleted before Emre's go). Everything ends before 21:45Z.

## Start here: 2026-10-13 = finish lab18 (`docs/second-lab-plan.md` §0, P58)

lab18 will be **down** in the morning (Emre's nightly automation stops it at ~21:46Z and downgrades the disks; P50/P51).
Every lab run ends before **21:45Z**. Report each milestone to the owner (the vezir).

1. **Restart** (pre-approved, P51; do **not** restore disk SKUs; disk-latency findings = HDD lab artefact):
   `az vm start -g rg-lab18 -n dc` first (DNS), then vm1 (real VM name in `files/private-refs.md`), then arc1. Wait
   until `v arc1 hostname` answers. Health: `tests/run.sh T04 vm1`, `T04 arc1`, `T06 vm1`, `T06 arc1`.
2. **T08 reboot**: `tests/run.sh T08 arc1`, then `T08 vm1` (vm1 was green on rc.7; this confirms rc.9). The test
   restarts the VM itself (`az vm restart`): a lab test action, not the product (P53).
3. **T06f part 2, arc1, last of all arc1 tests**: `tests/run.sh T06f arc1` installs IIS + ASP.NET 4.x (lab step); pass =
   G3 lines appear within 30 min, collector equals the expected list. IIS stays on arc1 until the teardown.
4. **P30 least privilege**: the lab SP gets **SRE Agent Author + Standard User** on the lab agent (agent resource only),
   Administrator removed for the trial; `scripts/deploy-skill.sh skill/perfmon-triage` dry run, then `--apply`
   (SRE_AGENT_ID: the agent's resource ID, from `azd env get-value SRE_AGENT_NAME` in `.lab/perfmon-blackbox`), then one
   T15 question. Pass → README/security.md document Author + Standard User. Fail → record the error, put
   Administrator back (the harness needs it until the teardown).
5. **Teardown list for Emre's final go**: enumerate **live** from lab18 and send to the owner. **Delete nothing before
   the go.** It must name: policy assignments `pbb-vm`, `pbb-arc-storage`, `pbb-gc-prereq` and their identities' role
   assignments (incl. the ABAC-conditioned RBAC Administrator on the storage, Deployer on the RG, the per-machine Writer
   and package Reader assignments); policy definitions `perfmon-blackbox-*` (all four kinds); the two custom roles
   (`az role definition list --custom-role-only true`, they outlive the RG); the lab SP's agent role (P30); the
   resource group via `cd .lab/perfmon-blackbox && direnv exec ../.. azd down --purge --force` (Key Vault purged); the
   Arc machine resource; leftover audit (template's lab audit); the lab register row (a request to the owner, same
   commit as the teardown). P52 (re-enable auto-shutdown) is superseded by the teardown; if the teardown is not
   approved, re-enable both schedules (command in P52).

**2026-10-14: the second lab** (P57/P58, GÜN-14): build after the teardown, README-only fresh-eyes deploy in storage
mode, then the full suite on vm1 and arc1. Plan, cost (≈ 1.20 USD/h fixed, 0.110 USD per AAU observed) and timeline:
`docs/second-lab-plan.md`. Agent cap: **1000 AAU/month** on the new agent (P60, Emre; closes CAP-500).

## State at close (2026-10-12 17:45Z)

- **Package rc.9** (version 1.0.8, SHA in P54) published as a pre-release; on **vm1** (GitHub mode, `pbb-vm`) and
  **arc1** (storage mode, `pbb-arc-storage`, rc.9 in the `packages` container). Prerequisites `pbb-gc-prereq`.
  Lab-only `.lab/perfmon-blackbox/pbb-package.env` = rc.9 (rc.8/rc.7 backups beside it).
- **Skill v2.2** live on the lab agent, identical to `skill/perfmon-triage/` (deploy-skill dry run 15:57Z).
- **Green today**: T18b–f (T18d/e on arc1 per P56), T10d, T10e (vm1's real cut ring; T10e.sh fixed for timing), T07b
  arc1 (computed, 26.4 h), T16 run 5 = 100 on both, **T17 vm1 100, arc1 95** (R1: an unmarked causal claim). Evidence
  (masked): `files/test-runs/261012-lab18/`. Statuses: `docs/tests.md`.
- **Docs pass done** (P59, 345ce3f): name uniqueness for a second deployment (custom role names tenant-wide, policy
  definition names per subscription), explicit custom-role removal, the SRE Agent's cost in `cost.md` and README.
- **Lab extras still in place**: arc1; vm1 data disk `T:`; dc identity = lab verifier; lab SP = SRE Agent
  Administrator on the agent (P30). Auto-shutdown schedules disabled (P52). vm1 no longer holds an unreadable ring.
- lab18 is up now and will be stopped by the nightly automation (~21:46Z); nothing is running on it.

## Lab facts that bite (from sessions 2–3)

- The first Machine Configuration cycle after a new package only **tests**; the next applies: ~45 min end to end.
- A first-party service re-sync re-PUTs the guest assignment from the policy engine's last evaluation: after a
  definition update, **run a compliance scan before remediating** (P55), or the re-sync reverts the version.
- An unchanged re-PUT does not download again; a machine already on a package stays Compliant without the reader role
  (P56). ARM hides `contentUri` on GET: build a re-PUT body from the definition metadata (`tests/lab/T18de.sh`).
- `T01` on dc fails with "Failed to initialize DSC library" while dc's own GC agent (`gc_worker`, OSConfig baseline)
  runs: wait until no `gc_worker` process is left.
- T16/T17 `start` refuse when a scheduled export falls inside their window: start right after the 4-hourly export.
- `lab-policy.sh` `DEFS_ONLY=1` updates definitions without prerequisites, mode switch or remediation.
- `az` defaults to another subscription: `direnv exec . sh -c 'az account set --subscription "$AZURE_SUBSCRIPTION_ID"'`
  once (never print it). Drive (`files/`) refuses concurrent writes: write locally, copy at milestones.
- Masking: lab-policy's own output line "role … on <account>" shows the storage name unmasked in local task output
  (never in the repo); pipe through `perl -pe 's/stbb\w+/<account>/g'` when capturing it.

## Standing rules (decisions)

- P31: lab pre-releases rc.N under the rc.1 conditions without asking; **v1.0.0 is Emre's gate**.
- P50–P53: nightly stop ~21:46Z stays; no run crosses 21:45Z; restart pre-approved; never restore disk SKUs; the
  product never changes a machine's power state.
- P8: OPEN-1 (rule 6 `link_test`) and OPEN-2 (VERDICT CEILING) are Emre's; do not change rule 6 or the ceiling.

## Waiting on others

- Emre: the final go on lab18's teardown list (after §0); OPEN-1, OPEN-2 (P8); the v1.0.0 tag.
- The vezir: lab register edits (requests from here); the lab SP secret rotation noted in session 1 (R15).
