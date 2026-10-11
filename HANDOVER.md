# sreagent-playbook: repo index. 1 playbook (perfmon-blackbox); repo private, flips public on Emre's word; safety gates R10–R15 in place.

Index only (R12): repo-level status and links. **No playbook status here**: read the playbook's own HANDOVER, in a
session opened for that playbook (`pj-open PLAYBOOK=<name>`).

## Playbooks

| Playbook | HANDOVER |
|---|---|
| perfmon-blackbox | [playbooks/perfmon-blackbox/HANDOVER.md](playbooks/perfmon-blackbox/HANDOVER.md) |

## Repo-level status (2026-10-11)

- **Visibility: private.** Emre decided it goes public right after the first round (R2); the flip is done on his word
  through the vezir. Every commit is written as public already; full-history scrub clean.
- **Rules:** `CLAUDE.md` (one session = one playbook, R12; root changes are separate commits with a decision entry).
  Decisions `docs/decisions.md` (R1–R15). DoD `docs/definition-of-done.md`.
- **Safety:** `scripts/install-hooks.sh` once per clone (pre-commit, commit-msg, pre-push run
  `scripts/scrub-check.sh`). Denylists merged (R13): `files/source-data/*denylist*.txt` + `files/denylist-extra.txt`.
  Private names are written neutrally; real names and paths are in `files/private-refs.md` (Drive).
- **Credentials:** check only with `direnv exec . scripts/env-check.sh` (R15). A credential print incident on
  2026-10-11 (transcript only, nothing in git or Drive) was reported; rotation of the lab SP secret is with the vezir.
- **Labs:** playbook lab checkouts live in `.lab/<playbook>/` (gitignored, refused by the scrub check, R14) and are
  registered in the private lab template's register.
- **CI:** `.github/workflows/ci.yml` (scrub check without denylist, Python and shell syntax).

## Root changes log (each with its decision entry)

- 2026-10-11: first round: README, LICENSE (MIT), CLAUDE.md, docs/ (R1–R12, DoD), scrub check, hooks, CI.
- 2026-10-11: R13: scrub check merges every denylist; private extra denylist in files/.
- 2026-10-11: R14: playbook lab checkouts in `.lab/` (gitignored), scrub check refuses `.lab/`.
- 2026-10-11: R15: credentials checked only with `scripts/env-check.sh`.
