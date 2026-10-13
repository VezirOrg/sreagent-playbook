# perfmon-blackbox: SECOND LAB lab20 UP 2026-10-13 16:59Z (P67, shared with blog post 6); fresh-eyes v1.0.0 deploy steps 0-4 done, waiting for Compliant; VMs stop 19:00Z (P68), continues 10-14.

Playbook: **perfmon-blackbox**. Read `../../CLAUDE.md`, `CLAUDE.md`, this file, then `decisions.md` (P1–P66; the
latest are P60–P66) and **`docs/second-lab-plan.md`**. Every `az`/`azd` call runs as `direnv exec . <command>` from
the repo root. Lab scripts: `tests/run.sh <ID> [vm1|arc1]` (call a lab script via its repo path: `common.sh` resolves
the lab from `$0`).


## Live now (session 5, 2026-10-13)

- **lab20 UP** (rg-lab20, dc + vm1, no SQL, no Arc), built 16:32–16:59Z from the template; register row in the template
  repo. Agent cap 1000 AAU. Auto-shutdown kept: the VMs stop 19:00Z (P68); work continues 2026-10-14.
- Fresh-eyes deploy of v1.0.0 from the tag docs (storage mode, `ExportEveryHours="1"`): steps 0–4 done 17:01–17:28Z;
  guest assignment Pending at 17:28Z. Doc findings F1–F7 (v1.0.x): local notes `.lab/lab20-logs/fresh-eyes.md`, copied to
  `files/post6-shots/` at milestones. **F2 matters**: deploy.md step 2 drops the definition metadata.
- Lab-only extras to remove at teardown: dc identity Blob Data Contributor on `packages` (upload host), lab SP SRE Agent
  Author + Standard User on the agent, gc-prereq assignment + its Contributor, pbb-vm-storage + its 4 role assignments,
  definition `perfmon-blackbox-vm-storage`, the two custom roles. Teardown only on Emre's go (list to the vezir).

## Where it stands

- **Released:** tag `perfmon-blackbox/v1.0.0` on e0005bf,
  https://github.com/VezirOrg/sreagent-playbook/releases/tag/perfmon-blackbox/v1.0.0 (Latest). Asset `PerfmonBlackbox.zip`,
  SHA-256 `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`, the rc.11 zip byte for byte (package label
  1.0.10 in the lab; adopters pass `--version 1.0.0`). Skill perfmon-triage v2.2.
- **Tested:** every planned stage test green on rc.11 on the Azure VM (vm1) and the Arc server (arc1)
  (`docs/tests.md` "rc.11 on lab18"): T04, T06, T07, T08 (rate across a boot), T09–T11, T19 (15-min roll merged),
  T07b, T15, T06f part 2 (IIS auto-detect); T16/T17 scores 95–100 earlier (rc.8/rc.9, skill unchanged since).
- **No lab is up.** lab18 was torn down 2026-10-13 15:32Z (P65): register row DOWN in the private lab template,
  its lab-audit CLEAN. `.lab/perfmon-blackbox/` (local, never committed) still holds the lab18 env files.
- **Docs for outside readers:** README (status v1.0.0, flow diagram `docs/img/perfmon-blackbox-flow.svg`, Turkish
  copy `.tr.svg`), `docs/deploy.md` complete (clone at the tag, VM prerequisites, v1.0.0 asset/SHA/version, agent
  identities, the RoleAssignmentExists trap). The blog session may ask for the release link, deploy.md and the SVG
  (stable URLs at the tag).

## What session 4 did (2026-10-13)

P60 CAP-1000 (second lab agent cap 1000 AAU/month); P61 KALSIN (skill stays on `deploy-skill.sh`); T08 arc1 red on
rc.9 (an unclosed ring after a long Windows Update preshutdown) → research, salvage, RELOG-DENE → **rc.10** (P62: roll
every 15 min) → **rc.11** (P63: relog merge per segment with probe, guard and fallback; DST-A UTC normalisation;
SKILL-SONRA: the skill's range-mode DST limit is post-v1.0.0); P64 (Author + Standard User suffice); rc.11 green on
both; the flow diagram; P65 teardown; P66 v1.0.0.

## Next

1. **Second lab, 2026-10-14** (`docs/second-lab-plan.md`): build from the private lab template, then a
   **README-only fresh-eyes deploy** of v1.0.0 (only what an adopter reads), agent cap 1000 AAU/month (P60). Every
   finding becomes a v1.0.x fix (docs first). Runs end before 21:45Z.
   - **Note:** Emre is being asked whether the second lab is shared with blog post 6; the vezir passes on his answer.
     Wait for it before building.
2. **Post-v1.0.0 items:** the skill's range mode across a DST fall-back (order rows by `Utc`; skill bump + T15–T17,
   P63 SKILL-SONRA); the package-reader step in storage mode should tolerate an existing assignment under another name
   (RoleAssignmentExists, tests.md "rc.11 on lab18"; documented in deploy.md for now).

## Open questions for Emre (asked through the vezir)

- **Delete the rc pre-releases** (`perfmon-blackbox/v1.0.0-rc.1` … `rc.11`)? Today they stay as lab history, marked
  superseded in the v1.0.0 notes. Options: delete all / keep all (current) / keep rc.11 only.
- **Second lab shared with blog post 6?** (the vezir relays the decision).
- OPEN-1 and OPEN-2 (P8) stay Emre's; do not change rule 6 or the VERDICT CEILING.

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

## Standing rules (decisions)

- P31: lab pre-releases rc.N without asking; a release (v1.x) is Emre's gate. The SHA goes into decisions.md before
  publishing; every file of a release zip is extracted and scrub-checked first.
- P50–P53: no lab run crosses 21:45Z; never restore disk SKUs; the product never changes a machine's power state.
- P8: OPEN-1 and OPEN-2 are Emre's.

## Waiting on others

- Emre (via the vezir): the rc pre-release question; the shared-lab question; OPEN-1, OPEN-2.
- The vezir: lab register edits for the second lab; the lab SP secret rotation noted in session 1 (R15).
