# CLAUDE.md: perfmon-blackbox (rules of this playbook only)

Shared rules: `../../CLAUDE.md`. Read `HANDOVER.md`, then `decisions.md`, before any work here.

- **Skill files.** `skill/perfmon-triage/` holds exactly the skill's files, flat (SKILL.md and its supporting
  files). Nothing else goes in that folder: `deploy-skill.sh` uploads every file in it. A skill change bumps
  `metadata.version` in SKILL.md and gets a CHANGELOG line.
- **Method questions OPEN-1 and OPEN-2** (decisions P8) are Emre's to decide. Do not change rule 6 or the VERDICT
  CEILING, in the skill or in the scoring rubric, until he does.
- **Masker = lab side.** `lab-tools/` is never shipped in the package or the skill.
- **Tests.** Every stage test runs with one command (`tests/run.sh <ID> [machine]`) and must pass on **both** the
  Azure VM and the Arc machine. Synthetic data only; the T16 ground truth comes from the synthetic load generator.
- **Stop conditions (P10).** If Machine Configuration cannot do a required step (e.g. the upload with the machine
  identity on Arc), or Arc cannot be tested in the lab: stop and report, do not work around.
