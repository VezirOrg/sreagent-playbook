# perfmon-blackbox: decisions

Numbered P1, P2, …; never renumbered. A changed decision gets a new number that says which one it replaces.
Repo-wide decisions: `../../docs/decisions.md`. Design proposals that still need Emre's approval are in
`docs/design.md` (section "Design choices for approval"), not here, until approved.

## P1: what it is (Emre, 2026-10-11)

A **black-box PerfMon recorder** for Windows servers. An **Azure Machine Configuration** package (DSC):

1. imports the logman (Data Collector Set) template,
2. starts the collector set,
3. re-starts it at every boot,
4. installs a **daily task**: relog the `.blg` to CSV, zip it, upload it to a **private storage account** with
   the **machine's own identity**, each machine **only into its own prefix**.

## P2: two policies (Emre, 2026-10-11)

**Two separate Azure Policy definitions**: one for **Azure VMs**, one for **Azure Arc-enabled servers**. Adopters
choose which one(s) to assign.

## P3: the skill (Emre, 2026-10-11)

The skill (v2) **reads storage**: finds the **latest** zip of a machine, downloads it, unzips it, converts the CSV
to SQLite, analyses. The agent publishes its recommendations **in the agent thread** for now (a GitHub issue
later). The trigger is **manual** for now.

## P4: phase 2 is decided (Emre, 2026-10-11)

An **Azure Monitor alert trigger** for the analysis is **phase 2**. It is decided and will be done; it is not in
v1.

## P5: success criterion (Emre, 2026-10-11)

**The latest zip can be analysed.** There is a test for **every stage**, end to end, the last one being the
analysis. Granular list (each one its own test, runnable with one command in the lab):

1. package builds and passes the local compliance test;
2. each policy definition and assignment exists, for Azure VM and for Arc;
3. guest assignment **Compliant** per machine;
4. extension and system identity present;
5. collector set **Running** with the template's counters, and the `.blg` growing;
6. **every** scheduled task exists with the right trigger and principal, and ran with result 0;
7. after a **reboot** the collector is running again;
8. the daily export makes a valid CSV and zip (header, rows, time range);
9. the blob lands at the expected path with a matching hash;
10. a machine **cannot** write into another machine's prefix;
11. the lifecycle rule is present;
12. the skill finds the latest zip, unzips, converts;
13. the agent produces the report from the latest zip, and the report is **scored**.

DoD centre: all stages green on a fresh lab, plus README-only fresh-eyes deploy, security (no secrets, scrub
clean, private storage, least privilege), cost per server written, CI green, tag + release, lab cleaned or
registered (see `../../docs/definition-of-done.md`). The test plan is `docs/test-plan.md`.

## P6: lab (Emre, 2026-10-11)

The project gets its **own lab**, built later from the **private lab template** and registered in the template repo's
`docs/labs.md`. For Arc testing, the lab follows the Learn guidance
[Evaluate Azure Arc-enabled servers on an Azure virtual machine](https://learn.microsoft.com/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine).
No lab and no Azure change before Emre approves the design and the test plan.

## P7: code brought in, with provenance (Emre, 2026-10-11)

Copied **verbatim** on 2026-10-11; any change to them is a later, separate commit. The blog repo was not edited
(its cleanup is a separate blog task).

| Here | Source | Source version | SHA-256 as copied |
|---|---|---|---|
| `skill/perfmon-triage/SKILL.md` | `sreagent-blog`: `files/post4-files/skill-v2/SKILL.md` (the blog's private Drive folder; **not in git**) | live skill v2 (front matter `version: "2.0"`), file dated 2026-10-11 08:58 +03; blog HEAD at copy time `b8fa4fb` | `51a8c88c87255cf9090c73dfea2c006bc21532d8f54f9d9e67e574047b24b001` |
| `skill/perfmon-triage/perfq.py` | same folder | same | `0e2713148d7f3fd2b8545433269515e76625145101f44269a60a1df2fb4a85f7` |
| `skill/perfmon-triage/perfmon_csv_to_sqlite.py` | same folder | same | `5f8afae7b25415a5472042ee4199f1de547659c3f1eb0d840ac542b3e789be2f` |
| `scripts/deploy-skill.sh` | same folder | same | `29af0b5ff630f8463b0bd999a0fac1e5adfd48c19cea9c5f1be88ce52302e1d9` |
| `lab-tools/perfmon_mask_csv.py` | `sreagent-blog`: `lab/perfmon_mask_csv.py` (in git) | commit `126dab65b07adfcc8d283dcec509251dadfee3b5` (blog D71: denylist check) | `a8dc38b7047320c4dd8ddd6b433a4bd6188bdf32f7ac80fc9d4d56d14531fff6` |

Notes:
- The skill-v2 folder's `UPLOAD.md` was **not** copied (it is a private upload checklist that points at private
  backup paths). `deploy-skill.sh` skips `.sh` files and `UPLOAD.md` when it builds the skill body, so the skill
  folder here holds exactly the three skill files.
- Comments in the masker cite "D68 rule b": that is blog decision D68 (the match rule). Here the same rule is used
  by `scripts/scrub-check.sh`.
- Before the copy entered the repo, all five files were checked with `scripts/scrub-check.sh` against the blog's
  64-entry denylist: clean.
- The masker is a **lab-side tool**: it is never part of the package or the skill. With this playbook the
  analysis reads the machine's own capture from the adopter's own storage, so masking is needed only when a real
  capture leaves its owner (e.g. for the blog); see design.

## P8: open method questions (Emre, 2026-10-11): **OPEN for Emre, not decided**

These are about the skill's method (SKILL.md rules). They are listed here so they are asked; nobody changes the
skill's behaviour on them until Emre decides.

- **OPEN-1 (RULE 6).** Rule 6 says every "because" needs a `link_test()`; without one, no cause is named ("coincides
  with"). Question: is that too strict (e.g. when the cause is obvious from one counter, or `link_test` does not
  apply because Y is not a load counter), or is it right as a hard rule?
- **OPEN-2 (5-minute VERDICT CEILING).** `triage()` caps the verdict at **warning** unless a check breached for 5
  continuous minutes. A **recurring 20–40 s stall** therefore stays a warning **even when the user names that stall
  as the problem**. Question: keep the ceiling as it is, or let a user-named, recurring short stall lift it (and by
  what rule)?

## P9: no Azure this round (Emre, 2026-10-11)

Round 1 = docs and safety only. Then the **PLAN GATE**: design (`docs/design.md`) and test plan
(`docs/test-plan.md`) go to Emre for approval through the vezir. No lab, no Azure change before his approval.

## P10: stop conditions (Emre, 2026-10-11)

Stop and report instead of working around if: a real name or a secret would enter the repo; **Machine
Configuration cannot do a required step** (for example the upload with the machine identity on Arc); **Arc cannot
be tested in a lab**.

## P11: counters = exactly Emre's 36 (Emre, 2026-10-11; replaces the counter list drafted in design §2.1)

The collector records **exactly the 36 counters of Emre's PerfMon template**, no more, no fewer. **Do not add
counters.** Where the skill loses inputs because of this, the gap is listed for Emre (design §2.5), not filled.

- Original: `files/emre-inputs/VitalSigns_Template.original.xml` (Drive; UTF-16; SHA-256
  `3ff1b9c63d2088e612767c0c26a11d6c30db04f756f6d65ab213cc8dc50f2af8`). It holds a **real machine name** (in
  `LatestOutputLocation`) and dated output paths, so it **never enters the repo as it is**.
- Committed instead (generated from the original by extracting only the `<Counter>` elements):
  `package/files/PerfmonBlackbox.counters.txt` (the 36 counters, verbatim) and
  `package/files/PerfmonBlackbox.template.xml` (sanitized Data Collector Set: those counters + the settings below;
  no machine name, no dated path, no `LatestOutputLocation`; UTF-8, because the scrub check refuses binary-looking
  UTF-16; the package converts it if `logman import` needs UTF-16).
- The machine name was not on the shared denylist: it is now in `files/denylist-extra.txt` (R13), and the vezir is
  asked to get it into the shared one.

## P12: the original's run settings are not taken over (Emre, 2026-10-11)

The original has `SampleInterval=1` and `Duration=10800` (3 h). A black box runs **continuously**: the template
has `Duration=0` and no schedule. The **sample interval is OPEN** (design CHOICE 1); it is not picked silently.

## P13: binary circular file, 512 MB (Emre, 2026-10-11)

The collector writes a **binary circular** log (`bincirc`; `logman … -f bincirc -max <MB>`): when the file reaches
its maximum it overwrites the oldest samples, so the **last MaxSizeMB of data is always on disk**. Default 512 MB.

## P14: MaxSizeMB is a policy parameter on both policies (Emre, 2026-10-11)

`MaxSizeMB` (integer MB, default **512**) is a **policy parameter** on **both** definitions (VM and Arc), passed to
the package as a Machine Configuration configuration parameter. Tests must prove: the file **never exceeds**
MaxSizeMB; it **really wraps** (oldest samples gone, newest present); a **changed value reaches the machine and
resizes** the collector.

## P15: export around the circular file (Emre, 2026-10-11; replaces design CHOICE 2 of the first draft)

The export covers **the window since the last successful export, with no gap and no overlap**. The design states
how many hours 512 MB holds at 1 s and at 15 s for this counter set (estimate now, **measured in the lab**), and
what happens when the window outgrows the buffer: **data loss is detected and reported in the manifest**.
