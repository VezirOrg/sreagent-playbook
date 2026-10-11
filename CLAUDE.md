# CLAUDE.md: sreagent-playbook (shared rules)

Multi-solution repo of reference implementations for Azure SRE Agent. **Public**: treat every commit, file name
and commit message as published the moment it is made.

## Start here: one session = one playbook (R12)

1. **Know your playbook.** A session works on exactly one playbook. It is named by whoever opened you (today in
   the opening request; later by the rig as `pj-open PLAYBOOK=<name>`, which puts you in that playbook's own git
   worktree). Name it at the top of your work and in every HANDOVER entry you write. If nobody named one and the
   request is not an explicit root change (rule 4), ask your owner before you write anything.
2. **Read, in this order:** this file; then the playbook's `CLAUDE.md` (if it has one), `HANDOVER.md` and
   `decisions.md` (paths in the index below). The root `HANDOVER.md` only links to them; it holds no playbook
   status.
3. **Write only under `playbooks/<your playbook>/`.** That includes its HANDOVER, decisions, docs, code and tests.
4. **Root changes are separate.** A change to root files (`CLAUDE.md`, `README.md`, `HANDOVER.md`, `LICENSE`,
   `docs/`, `scripts/`, `.githooks/`, `.github/`, `.gitignore`) or to `shared/` is its own explicit change: a new
   entry in `docs/decisions.md` first, then its own commit(s). Never mix it into a playbook commit. The root
   `HANDOVER.md` changes only when a playbook is added or removed, or for repo-level status.
5. **Worktrees (planned, not built yet).** With more than one playbook, each runs in its own worktree and branch
   and merges to `main`; parallel sessions do not conflict because each writes only its own folder. Until then,
   work on `main`, and still keep the commits separate as in rule 4.
6. Repo-wide decisions: `docs/decisions.md`. Definition of done: `docs/definition-of-done.md`.

## Playbook index

| Playbook | Path | Purpose | First read |
|---|---|---|---|
| perfmon-blackbox | `playbooks/perfmon-blackbox/` | Black-box PerfMon recorder (Machine Configuration on Azure VMs and Arc servers) plus the SRE Agent skill that analyses the latest capture of a machine | `playbooks/perfmon-blackbox/HANDOVER.md` |

No status here; status lives in each playbook's HANDOVER. Adding a playbook = a root change (rule 4): a row
here, a link in the root `HANDOVER.md` and the README table, and a decision entry.

## Shared rules

- **Wiki first.** A decision is written into the right `decisions.md` before the work that follows from it.
  Repo-wide decisions go in `docs/decisions.md`; playbook decisions in `playbooks/<name>/decisions.md`.
- **HANDOVER rule (Emre, R8).** A playbook's `HANDOVER.md` is updated at every critical moment (a stage green or
  red, a design change, a blocker, a lab built or torn down) and at session close. The root `HANDOVER.md` too, but
  it is an index only (R12): repo-level status and links, never a playbook's status. Its first line is what the
  rig shows.
- **Hooks.** After every fresh clone run `scripts/install-hooks.sh`. pre-commit, commit-msg and pre-push run
  `scripts/scrub-check.sh`. Never bypass them (`--no-verify` is forbidden). A hit is fixed, not allowed-listed,
  unless it is a well-known public value (then `scripts/scrub-allow.txt`, with a comment).
- **Denylist.** The scrub check needs the private denylist at `files/source-data/denylist.txt` (or
  `SCRUB_DENYLIST=<path>`). It is never committed. Without it the check fails closed.
- **Data.** Tests use **synthetic data only** (`playbooks/*/tests/fixtures/synthetic/`). Real or masked third-party
  data never enters the repo: it stays in `files/` (Google Drive, gitignored). Real names never appear in code,
  docs, test names, commit messages or blob paths shown in docs. Private names (private repos, the lab template,
  lab paths) are written neutrally ("the private lab template"); the real names and paths are in
  `files/private-refs.md`, never here.
- **Secrets.** `.env` (a symlink to the lab credentials), `.envrc` (local az/azd config dirs) and `files/` are
  gitignored and never committed. Run every `az`/`azd` command as `direnv exec . <command>`. Never print a secret
  value: print its name or its length.
- **Layout per playbook.** `playbooks/<name>/` holds `README.md` (adopter guide), `HANDOVER.md`, `decisions.md`,
  `CHANGELOG.md`, `tests/`, and a `CLAUDE.md` only if it has rules of its own.
- **Releases.** Tags are `<name>/vX.Y.Z`. Release packages (zips) are GitHub Release assets, never committed.
- **Provenance.** Code copied from elsewhere is recorded in the playbook's `decisions.md`: source repo, commit (or
  path and date if the source is not in git) and SHA-256 of each file as copied.
- **Licence.** Code is MIT ("the sreagent-playbook authors"). Blog posts are CC BY 4.0 and live in the blog repo,
  not here. The README says: not an official Microsoft product.
- **Azure.** Each playbook tests in its own lab, built from the private lab template and registered in
  the template repo's `docs/labs.md` in the same commit as the build or teardown. No Azure change without an approved plan.
- **Stop conditions.** Stop and report (do not work around) when: a real name or secret would enter the repo; a
  platform cannot do a required step; a required path cannot be tested in a lab.
