# sreagent-playbook: repo index. 1 playbook (perfmon-blackbox); repo private, flips public on Emre's word; safety gates in place.

Index only (R12): repo-level status and links. **No playbook status here**; read the playbook's own HANDOVER.

## Repo-level status (2026-10-11)

- Visibility: **private**. Emre decided it goes **public right after the first round** (R2); the flip is done on
  his word through the vezir. Every commit is written as public already.
- Safety: `scripts/scrub-check.sh` + hooks in `.githooks/` (pre-commit, commit-msg, pre-push). Run
  `scripts/install-hooks.sh` after every fresh clone. The denylist is expected at `files/source-data/denylist.txt`
  (copied there by the blog session; until then set `SCRUB_DENYLIST`, see `docs/decisions.md` R10).
- CI: `.github/workflows/ci.yml` (scrub check without denylist, Python and shell syntax).
- Rules: `CLAUDE.md` (one session = one playbook, R12). Decisions: `docs/decisions.md`. DoD:
  `docs/definition-of-done.md`.

## Playbooks

| Playbook | HANDOVER |
|---|---|
| perfmon-blackbox | [playbooks/perfmon-blackbox/HANDOVER.md](playbooks/perfmon-blackbox/HANDOVER.md) |

## Root changes log (each with its decision entry)

- 2026-10-11: first round: README, LICENSE (MIT), CLAUDE.md, docs/ (R1–R12, DoD), scrub check, hooks, CI.
