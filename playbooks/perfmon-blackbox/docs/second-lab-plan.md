# Second-lab fresh-eyes deploy: build plan (DRAFT for Emre's approval)

> **Status: draft, 2026-10-12 (P57). Option A decided (P58). OPEN: the day (proposed 2026-10-14) and the 500-AAU cap.
> Nothing is torn down or built, and no Azure change is made for it, until Emre's final go on the teardown list.**
> Purpose: DoD item 2 (`../../../docs/definition-of-done.md`): someone with no access to the record deploys the
> playbook into a clean lab **from the README alone** and gets the stage suite green; every gap found is fixed in the
> README before v1.0.0. The same lab also gives the DoD-1 "all stages green on a freshly built lab" run.

## 0. Before: finish lab18 (2026-10-13, P58)

Lab day after the nightly stop (restart pre-approved, P51), every run ends before 21:45Z:

| Order | Item | Machine change | Time |
|---|---|---|---|
| 1 | Restart dc, vm1, arc1; health: T04, T06 on both | none | ~0.5 h |
| 2 | **T08 reboot on arc1** (the test restarts the VM itself, `az vm restart`: a lab test action, not the product, P53); also on vm1 to confirm rc.9 (vm1 was green on rc.7) | OS restart | ~0.5 h |
| 3 | **T06f part 2 on arc1**: IIS + ASP.NET 4.x installed (lab step), G3 lines appear within 30 min, no sample lost. Done after T08 and after every arc1 analysis test, because IIS changes arc1's baseline | IIS on arc1 (stays until teardown) | ~0.75 h |
| 4 | **P30 least privilege**: the lab SP gets SRE Agent Author + Standard User on the lab agent, Administrator removed for the trial; `deploy-skill.sh` dry run and `--apply`, then one T15 question. Pass → README documents Author + Standard User; fail → the error is recorded and the README keeps Administrator. Administrator is put back afterwards only if the trial fails (the test harness needs a working role until teardown) | role assignments on the lab agent | ~1 h |
| 5 | **Docs pass** (no lab): README, deploy, operations, security, cost; the tenant-wide custom-role-name note (section 2); the agent's always-on cost in `cost.md`; T17 and today's results | none | ~3 h |
| 6 | **Teardown list for Emre's final go**: enumerated live from lab18 (assignments, role assignments incl. ABAC-conditioned ones, definitions, custom roles, the SP agent role, resource group, Key Vault purge, Arc resource, register row) and sent to the vezir; nothing deleted before the go | none | ~0.5 h |

A package change is not expected. If one is needed, it is a new rc (P31) and the affected tests re-run on lab18.

## 1. What gets built

| Part | What | Who / how |
|---|---|---|
| Lab | A new lab from the private lab template, template defaults: domain controller `dc`, one Windows member server (`vm1` in the record), Bastion Standard, VNet with private DNS, Key Vault, Log Analytics + App Insights, the SRE Agent with VNet integration. Same shape as lab18 | Lab build script of the template; registered in the template repo's lab register in the same commit (a request to the owner, as for lab18) |
| Arc server | `arc1`: a B2s_v2 Windows Server 2022 VM onboarded to Arc per the Learn guide *Evaluate Azure Arc-enabled servers on an Azure virtual machine* (P6) | `tests/lab/lab-arc1.sh`, as in lab18 |
| The product | Private storage (`infra/main.bicep`), the two policy definitions, the assignments in **storage mode** (P45), remediation, the skill on the lab's agent | **The fresh-eyes session**: a new session that gets only the repo's public adopter docs (README → `docs/deploy.md` and the docs it links) and the lab's resource names. No HANDOVER, no decisions, no lab scripts, no help from me. It writes down every gap and every guess it had to make |
| Test extras (after the deploy, lab only, not part of the product) | `vm1` scratch data disk `T:` (T16 disk plant), the lab service principal as agent admin for the test harness (P30, removed at teardown), `dc` identity as the lab verifier (blob reads) | Me, with the existing lab scripts, after the fresh-eyes session has finished |
| Package | The rc that is meant to become v1.0.0 (today rc.9), the release zip unchanged, copied into the `packages` container | Fresh-eyes session, by the README |

**Then the suite** (me, one command per test, `tests/run.sh`): T13, T14, T01, T02–T05, T06, T07, T07b (computed, P56),
T08, T09, T10–T12, T15, T16 and T17 on `vm1` and `arc1`, T18 (storage mode) on both. Pass = the same green as lab18.
Every README gap found goes into the README before v1.0.0 (a docs commit, not a package change).

## 2. Where

Same subscription and region as lab18 (**Sweden Central**: SRE Agent available there, prices below are for it).
Resource group from the template's naming (the next free lab number in the register).

**Name clash (found while drafting, must be decided):** `infra/main.bicep` creates two custom roles with fixed display
names ("PerfMon Blackbox Writer", "PerfMon Blackbox Deployer"), and **custom role display names must be unique in the
whole Entra tenant** (Learn, *Azure custom roles*, roleName). The policy definitions are created at subscription scope
with fixed names (`perfmon-blackbox-<kind>`), so a second deployment in the same subscription would overwrite lab18's.
While lab18 still has its product deployed, a README-only deploy in the same tenant fails or interferes. Options:

| Option | What | For | Against |
|---|---|---|---|
| **A (DECIDED, P58)** | Finish and record lab18's remaining tests first; then tear lab18 down **including** its policy assignments, policy definitions and the two custom roles (they outlive the resource group and must be deleted explicitly); then build the second lab | The fresh-eyes session sees exactly an adopter's clean tenant; README stays as is; one lab's cost at a time | No fallback lab once lab18 is gone (the second lab becomes the lab until v1.0.0) |
| B | Keep lab18; the second lab uses other role and definition names | Both labs at once | The README has to teach a "second deployment in the same tenant" variant (role-name parameters, definition names), so the fresh-eyes run tests that variant, not the plain path; double cost |
| C | A different tenant/subscription | Cleanest isolation | Needs one (Emre's call); none is known to me |

Whatever the choice, the README gets a note: the custom role names are tenant-wide, a second deployment in the same
tenant must pass other names (`writerRoleName`, `deployerRoleName`). This is an adopter gap regardless of the lab.

## 3. Cost per hour

Measured on lab18 (Azure Cost Management, actual cost, 2026-10-11/12; retail USD) and the Azure Retail Prices API
(Sweden Central, 2026-10-12):

| Item | USD / hour | Source |
|---|---|---|
| SRE Agent always-on flow, 4 AAU per agent-hour (Learn, *Pricing and billing for Azure SRE Agent*) | **0.44** | lab18 billed 0.110 USD per AAU (51.03 USD for 463.87 AAU on 10-11) |
| Bastion Standard | 0.29 | Retail API |
| 3 × B2s_v2 Windows (`dc`, `vm1`, `arc1`) | 0.29 | Retail API 0.0956 each; lab18 actual 0.093 |
| Defender for Servers P2 (subscription plan, ~3 nodes) | ~0.06 | lab18 actual 0.02 per node-hour |
| Log Analytics ingestion | ~0.07 | lab18 actual 10-11 (1.66 USD/day) |
| Private endpoints (~3), public IP, disks, Arc Machine Configuration (6 USD/server/month) | ~0.07 | lab18 actual + Retail API |
| **Fixed, while the lab exists** | **≈ 1.20** | |
| SRE Agent **active flow** (the analyses: T15, T16 × 2, T17 × 2, plus the fresh-eyes session's own questions) | variable | lab18's heaviest test day (10-11) used ≈ 370 AAU active ≈ 40 USD |

**Budget for one day (≈ 10 h):** ≈ 12 USD fixed + ≈ 20–40 USD active flow ≈ **35–55 USD**. Guard: the second lab's
agent gets the minimum monthly active-flow allocation (**500 AAU ≈ 55 USD**, Learn: min 500): if a loop runs away, the
agent stops answering instead of spending more. If the lab has to stay overnight, ≈ 0.8 USD/h (agent always-on +
Bastion + PEs; VMs stopped by the nightly lab automation) ≈ 11 USD a night.

## 4. How long it runs

One working day, inside the P51 window (every lab run ends before 21:45Z):

| Time (UTC) | Step | Duration |
|---|---|---|
| 06:00 | build the lab (template) + `arc1` onboarding | ~1.5 h (estimate; lab18's build was not timed) |
| 07:30 | fresh-eyes session: README-only deploy (storage mode), skill upload | ~1.5 h |
| 09:00 | wait for compliance (first cycle tests, the next applies: ~45 min; P55 scan before remediation) | ~1 h |
| 10:00 | stage suite on `vm1` and `arc1`, T16 + T17 last (≈ 50 min each, both machines in parallel) | ~5 h |
| 15:00 | README gaps recorded; teardown, leftover check, register update | ~0.5–1 h |
| **16:00** | **lab gone** | **≈ 10 h** |

A red test that needs a package fix does not keep the lab up overnight by default: the lab is torn down and rebuilt
for the re-run (≈ 3 h), unless Emre says to keep it.

## 5. Teardown

1. Remove the policy assignments and their identities' role assignments (storage and package container), the policy
   definitions, and the two custom roles (after their assignments are gone: Azure refuses to delete a role in use).
2. Remove the lab service principal's agent role (P30).
3. Lab template teardown (`azd down --purge --force`), which deletes the resource group with the agent, VMs, Arc
   machine resource, storage, Key Vault (purged).
4. Leftover check with the template's lab audit: no resource group, no orphan role assignments, definitions or custom
   roles, no Key Vault in soft-delete, no Arc machine resource.
5. Register updated (request to the owner) in the same commit as the teardown; HANDOVER updated.
6. The fresh-eyes notes stay in `files/` (masked); the README fixes go into the repo before v1.0.0.

## 6. What Emre decides

1. ~~Option A, B or C for the name clash~~: **A** (P58).
2. The day (proposed 2026-10-14). OPEN.
3. The active-flow cap (500 AAU) for the second lab's agent. OPEN.
4. The final go on lab18's teardown list (sent after section 0, item 6).
