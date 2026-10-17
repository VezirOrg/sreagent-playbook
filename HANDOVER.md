# sreagent-playbook: repo index. 2 playbooks released (perfmon-blackbox v1.0.2, sql-mcp v1.0.0); repo PUBLIC; "Latest" stays put (R22).

Index only (R12): repo-level status and links. **No playbook status here**: read the playbook's own HANDOVER, in a
session opened for that playbook (`pj-open sreagent-playbook PLAYBOOK=<name>`).

## Playbooks

| Playbook | HANDOVER |
|---|---|
| perfmon-blackbox | [playbooks/perfmon-blackbox/HANDOVER.md](playbooks/perfmon-blackbox/HANDOVER.md) |
| sql-mcp | [playbooks/sql-mcp/HANDOVER.md](playbooks/sql-mcp/HANDOVER.md) |

## Repo-level status (2026-10-17)

- **Visibility: PUBLIC** (Emre's word; R19). Every commit is published the moment it is pushed; hooks and CI run the
  scrub check.
- **Rules:** `CLAUDE.md` (one session = one playbook, R12; root changes are separate commits with a decision entry).
  Decisions `docs/decisions.md` (R1–R22). DoD `docs/definition-of-done.md`.
- **Releases:** per-playbook tags `<playbook>/vX.Y.Z`, the package zip as the only asset (R6). GitHub's repo-wide
  "Latest" badge stays where it is (perfmon-blackbox v1.0.2); new releases use `--latest=false` unless Emre says
  otherwise (R22). Release assets bypass the git hooks: every file in a zip and the notes are scrub-checked before the
  upload.
- **Safety:** `scripts/install-hooks.sh` once per clone (pre-commit, commit-msg, pre-push run
  `scripts/scrub-check.sh`). Denylists merged (R13): `files/source-data/*denylist*.txt` + `files/denylist-extra.txt`.
  Private names are written neutrally; real names and paths are in `files/private-refs.md` (Drive).
- **Credentials:** check only with `direnv exec . scripts/env-check.sh` (R15). The lab SP secret was rotated on
  2026-10-17 by the vezir. azd in this repo signs in through az's login (`.azd-config`: `auth.useAzCliAuth true`,
  sql-mcp S15; undo `azd config unset auth.useAzCliAuth`).
- **Labs:** playbook lab checkouts live in `.lab/<playbook>/` (gitignored, refused by the scrub check, R14) and are
  registered in the private lab template's register. No playbook lab is up (lab21 torn down 2026-10-17).
- **CI:** `.github/workflows/ci.yml`: scrub check (no denylist), Python and shell syntax, perfmon-blackbox local and
  Windows tests (R18), sql-mcp local tests and L01 under Windows PowerShell 5.1 (R21).
- **Untracked, not ours to touch:** `playbooks/perfmon-blackbox/package/files/` (counter and template files from
  2026-10-11; R16 says that playbook uses `package/collector/`). For a perfmon-blackbox session to sort out.

## Root changes log (each with its decision entry)

- 2026-10-11: first round: README, LICENSE (MIT), CLAUDE.md, docs/ (R1–R12, DoD), scrub check, hooks, CI.
- 2026-10-11: R13: scrub check merges every denylist; private extra denylist in files/.
- 2026-10-11: R14: playbook lab checkouts in `.lab/` (gitignored), scrub check refuses `.lab/`.
- 2026-10-11: R15: credentials checked only with `scripts/env-check.sh`.
- 2026-10-11: R16–R19: `.gitignore` root `files/` only; built-in role IDs allow-listed; CI runs perfmon-blackbox
  tests; the repo is public.
- 2026-10-17: R20: second playbook `sql-mcp` added to the index.
- 2026-10-17: R21: CI runs the sql-mcp local tests (Ubuntu, and L01 under Windows PowerShell 5.1).
- 2026-10-17: R22: "Latest" stays where it is; each playbook is found by its own tag (`--latest=false`).
