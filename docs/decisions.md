# Repo-wide decisions

Only decisions that hold for the whole repository. Playbook decisions live in `playbooks/<name>/decisions.md`.
Numbered R1, R2, …; never renumbered. A changed decision gets a new number that says which one it replaces.

## R1: what this repo is (Emre, 2026-10-11)

`VezirOrg/sreagent-playbook` is a multi-solution repository of reference implementations ("playbooks") for Azure
SRE Agent. They are working and versioned, with **no support promise**. The README says: **not an official
Microsoft product**.

## R2: public from the first commit (Emre, 2026-10-11)

The repository becomes **public** right after the first round (docs and safety). Every commit, file name and
commit message is treated as public from the first one. (The rig's default for project repos is "private"; Emre's
word for this repo overrides it.) Flipping the visibility is done on Emre's word through the vezir, not by a
project session on its own.

## R3: licences (Emre, 2026-10-11)

- Code in this repo: MIT, copyright line "the sreagent-playbook authors" (`LICENSE`).
- Blog posts: CC BY 4.0. They live in the blog repo (`sreagent-blog`, published at sreagent.emreguclu.io), never
  here.

## R4: blog and repo (Emre, 2026-10-11)

The blog announces each playbook and carries the guides. Each post links to a **release tag** in this repo. The
repo carries the code, the adopter README, the tests and the record.

## R5: layout (Emre, 2026-10-11)

- Root `CLAUDE.md`: shared rules plus an **index** of playbooks (name, path, one-line purpose, "read its HANDOVER
  first"). No status in it.
- Root `HANDOVER.md`: thin: repo status and links to each playbook's HANDOVER. The rig reads its first line.
- `docs/decisions.md`: repo-wide decisions only (this file). `docs/definition-of-done.md`: the DoD.
- `playbooks/<name>/`: its own `CLAUDE.md` (only if it has rules of its own), `HANDOVER.md`, `decisions.md`,
  `README.md`, `CHANGELOG.md`, `tests/`.

## R6: releases (Emre, 2026-10-11)

Per-playbook tags `<name>/vX.Y.Z`. A playbook's package (zip) is a **GitHub Release asset**, never committed.

## R7: data (Emre, 2026-10-11)

Tests use **synthetic data only**. Real or masked third-party data never enters the repo; it stays in `files/`
(Google Drive, gitignored). Source CSVs, mappings and the denylist are copied by the blog session into
`files/source-data/`.

## R8: HANDOVER rule (Emre, 2026-10-11)

Each playbook's `HANDOVER.md` is updated at every critical moment **and** at session close. The root
`HANDOVER.md` too.

## R9: credentials (Emre, 2026-10-11)

`.env` is a symlink to the lab credentials file; `.envrc` sets local az/azd config dirs. Every `az`/`azd` command
runs as `direnv exec . <command>`. Values are never printed. `.env`, `.envrc` and `files/` are gitignored and never
committed.

## R10: safety gates (2026-10-11, this round's ask from Emre)

`scripts/scrub-check.sh` plus versioned git hooks (`.githooks/`, installed by `scripts/install-hooks.sh`):

- **pre-commit** checks staged file names and contents; **commit-msg** checks the message; **pre-push** re-checks
  every commit being pushed (names, contents, messages), so a commit made before the hooks were installed is still
  caught.
- Blocked: `.env`/`.envrc` files, anything under `files/`, keys and certificates, capture and data files (`.blg`,
  `.etl`, `.db`, `.sqlite`, `.zip`, …), mapping/denylist files, CSV files outside
  `playbooks/*/tests/fixtures/synthetic/`, any binary file; secret patterns (storage keys, SAS signatures, JWTs,
  private keys, tokens, password assignments); GUIDs, private IPv4 addresses and e-mail addresses (except
  `scripts/scrub-allow.txt` and the commit trailer address); every **denylist name**.
- The denylist is read from `files/source-data/denylist.txt` (or `SCRUB_DENYLIST`), never committed, matched like
  the masker (case-insensitive; 5+ characters anywhere, shorter only as a whole word). **No denylist = fail.**
  CI has no denylist and runs with `SCRUB_ALLOW_NO_DENYLIST=1`, so the denylist gate is local (hooks) only.
- Output never shows the matched text: only check, place, and for the denylist the entry number and length.

Interim (2026-10-11): until the blog session copies the denylist into `files/source-data/`, the session points
`SCRUB_DENYLIST` at the blog project's private denylist (read-only, outside both repos).

## R11: labs (Emre, 2026-10-11)

Each project gets its **own** lab, built from the **private lab template** and registered in the template repo's
`docs/labs.md` (in the same commit as the build or teardown). No lab and no Azure change before Emre approves the
playbook's design and test plan (the PLAN GATE).

## R12: one session = one playbook (Emre, 2026-10-11)

1. A session works on **exactly one playbook**. It names that playbook at the top of its work and in its HANDOVER
   entries.
2. It reads the root `CLAUDE.md` plus that playbook's `CLAUDE.md`, `HANDOVER.md` and `decisions.md`, and writes
   **only under `playbooks/<its name>/`**.
3. Changes to `shared/` or to root files (`CLAUDE.md`, `README.md`, `docs/`, CI, `scripts/`, `.githooks/`) are
   **separate, explicit changes with their own decision entry** in this file. They are never mixed into a
   playbook commit.
4. The root `HANDOVER.md` is an **index only**: repo-level status and links to each playbook HANDOVER. A playbook
   status never lives there, so parallel sessions never conflict on it. (The same holds for the root README and
   `CLAUDE.md`: no playbook status.)
5. **Planned, not built yet:** when a second playbook arrives, the rig gets `pj-open PLAYBOOK=<name>`, with one
   git worktree per playbook and merges to `main`. `CLAUDE.md` is written so it already reads correctly for that
   future.

First application (2026-10-11): the repo's first round touches both root files and the first playbook; it is
committed as separate commits: root (R1–R12, shared safety tooling, root docs) first, then
`playbooks/perfmon-blackbox/` alone.

## R13: every denylist is merged; private extra denylist (2026-10-11, on Emre's input via the vezir)

- `scripts/scrub-check.sh` merges **all** denylists it finds: every path in `SCRUB_DENYLIST` (`:`-separated),
  every `files/source-data/*denylist*.txt` (the blog session's copy, R7), and `files/denylist-extra.txt`. Fail
  closed if none is found (unchanged). Hits are reported as `L<list>#<entry>` and length, never the name.
- `files/denylist-extra.txt` (Drive, never committed) holds names this project found that the shared denylist
  lacks. First entries (2026-10-11): the machine name in Emre's original PerfMon template (its
  `LatestOutputLocation`), full and its long part. The vezir is asked to get them into the shared denylist too.
- The R10 interim (pointing `SCRUB_DENYLIST` at the blog's list) ends: `files/source-data/` now holds the
  denylist.

## R14: a playbook's lab project lives in `.lab/`, gitignored (2026-10-11, for LAB-KUR, P16 of perfmon-blackbox)

A playbook lab is built from the private lab template with `azd init -t <template> --branch <tag>`. That checkout
holds the private template, so it must never enter this public repo: it lives in `.lab/<playbook>/` (gitignored)
and is driven with `direnv exec <repo root> azd …` (this repo's `.env` and local az/azd config dirs). The lab is
registered in the template's lab register, in the template repo, in the same commit as its build or teardown.

Addendum (2026-10-11): `azd init` ran `git add` in the parent repo and staged template scripts despite the
gitignore; they were unstaged before any commit. The scrub check now refuses any path under `.lab/` (pre-commit and
pre-push), so a forced add cannot slip through.

## R15: credentials are checked only with `scripts/env-check.sh` (Emre via the vezir, 2026-10-11)

After a session printed credential values by an ad-hoc shell expansion meant to print lengths (2026-10-11; nothing
reached git or Drive; rotation is Emre's call), the rule is: check that credentials load **only** with the vetted
`direnv exec . scripts/env-check.sh [NAME ...]`, which prints name, set/unset and length, never a value. No ad-hoc
`echo`, `printf`, `eval`, `env`, `set` or parameter expansion on credential variables, ever.

## R16: `.gitignore` ignores only the root `files/` link (the vezir, 2026-10-11)

The pattern `files/` also matched any `files/` folder deeper in the tree, so a playbook's `package/files/` was silently
never committed (perfmon-blackbox P20). The pattern is now `/files` and `/files/`: only the root Drive link is
ignored. A playbook may still not name a folder `files/` by habit; perfmon-blackbox uses `package/collector/`.

## R17: built-in role definition IDs used by perfmon-blackbox are allow-listed (the vezir, 2026-10-11)

The scrub check flags every GUID. Built-in Azure role definition IDs are public constants: the three that
perfmon-blackbox's infra and policy definitions must name (Storage Blob Data Reader, Guest Configuration Resource
Contributor, Role Based Access Control Administrator) are in `scripts/scrub-allow.txt`, exact IDs only, never a
pattern, each verified read-only (`az role definition list --name <id>`: roleType BuiltInRole) with its role name in
the comment.

**R17 addendum (2026-10-11):** the built-in **Reader** role ID is allow-listed too (verified BuiltInRole): the
perfmon-blackbox DINE identity must read the machine to pass its identity to the per-machine role assignment.

## R18: CI runs the perfmon-blackbox tests (the vezir, 2026-10-11)

`.github/workflows/ci.yml` runs perfmon-blackbox's local tests (synthetic data) in the `checks` job, and a
`perfmon-blackbox-windows` job on `windows-latest`: Pester L05 and the PSScriptAnalyzer Windows PowerShell 5.1 rules
under `powershell.exe`, then the package build (authoring side, PowerShell 7). Nothing in CI touches Azure.

## R19: the repo is public (the vezir, 2026-10-11, recording Emre's word)

The repository is **public** by Emre's word (as the opening briefs and CLAUDE.md already treat it). The root
`HANDOVER.md` said "private, flips public on Emre's word": corrected. Nothing else changes: every commit was already
written as public.

## R20: second playbook `sql-mcp` (Emre via the vezir, 2026-10-17)

A second playbook, **`sql-mcp`**, is started at `playbooks/sql-mcp/`: a read-only SQL Server DMV MCP server (Data API
builder's MCP endpoint, Windows auth with a gMSA, no object on the SQL Servers) that Azure SRE Agent calls over the
VNet with its managed identity, locked by an Entra app role. It turns an earlier private research project into (a) a
lab that can be rebuilt with one command and (b) a released playbook in the perfmon-blackbox shape (tag
`sql-mcp/vX.Y.Z`, zip as a release asset, CHANGELOG, quick install in Turkish and English). The audience is both a
real adopter need and the blog.

- Root changes of this entry: a row in the `CLAUDE.md` index, a link in the root `HANDOVER.md`, a row in the README
  table. The playbook scaffold is a separate commit (R12).
- **Plan gate (R11):** no lab, no Azure change and no code beyond the scaffold until Emre approves the playbook's
  inventory and plan (kept in Drive, not here).
- Worktrees (R12.5) are still not built: the session works on `main` and writes only under `playbooks/sql-mcp/`.

## R21: CI runs the sql-mcp local tests (the vezir, 2026-10-17; sql-mcp plan v1, approved by Emre)

`.github/workflows/ci.yml` runs sql-mcp's local tests: in the `checks` job (Ubuntu, PowerShell 7 preinstalled) L01
(the DAB configuration generator), L02 (the Windows PowerShell 5.1 lint; PSScriptAnalyzer saved to a temp folder) and
L03 (the deterministic package); and a `sql-mcp-windows` job on `windows-latest` that runs L01 again under Windows
PowerShell 5.1 (`powershell.exe`), where the scripts really run. L04 (DAB drift, GitHub API) stays local: a new upstream
release is a signal for a playbook session, not a broken build. Nothing in CI touches Azure.
