# perfmon-blackbox: round 1 done (docs + safety); design and test plan wait at the PLAN GATE for Emre. No Azure yet.

Playbook: **perfmon-blackbox** (R12: sessions name their playbook). Read `decisions.md` next.

## Where it stands (2026-10-11, end of session 1)

- Emre's decisions of 2026-10-11 are recorded: `decisions.md` P1–P10 (what, two policies, skill, phase 2, success
  criterion, lab, provenance, OPEN method questions, no Azure this round, stop conditions).
- **PLAN GATE, waiting for Emre:** `docs/design.md` (with CHOICE 1–7, each with a recommendation) and
  `docs/test-plan.md` (T01–T16 lab, L01–L06 local). **No lab and no Azure change before his approval.**
- **OPEN for Emre (P8):** OPEN-1 (rule 6: every "because" needs a `link_test`) and OPEN-2 (5-minute VERDICT
  CEILING keeps a user-named recurring 20–40 s stall at warning). Not decided; do not change the skill on them.
- Code brought in verbatim with provenance (P7): skill v2.0 (`skill/perfmon-triage/`), `scripts/deploy-skill.sh`,
  `lab-tools/perfmon_mask_csv.py`. Scrub-checked against the denylist before the commit: clean.
- Feasibility on paper (design §7): Arc upload with the machine identity works through HIMDS for a SYSTEM task;
  Arc can be evaluated on an Azure VM per Learn. Both are proven only in the lab (T05/T11 on `arc1`). Stop
  conditions P10 apply if not.

## Next (only after Emre's approval of the plan)

1. Fold his answers to CHOICE 1–7 into `decisions.md` (new P numbers).
2. Build `package/`, `policy/`, `infra/`, local tests L01–L06 and CI for them.
3. Build the lab from the private lab template (name and path: `files/private-refs.md`), register it there first.
4. Run T01–T16 on `vm1` and `arc1`.

## Waiting on others

- The blog session copies source CSVs, mappings and the denylist into `files/source-data/` (R7). Until the
  denylist is there, commits need `SCRUB_DENYLIST` set to the blog's private denylist (path in
  `files/private-refs.md`); without it the hooks fail closed.
