# sql-mcp: decisions

Numbered S1, S2, …; never renumbered. A changed decision gets a new number that says which one it replaces.
Repo-wide decisions: `../../docs/decisions.md` (this playbook was started by R20).

## S1: what it is and why (Emre via the vezir, 2026-10-17)

A **read-only MCP server for SQL Server dynamic management views**, built on Data API builder's MCP endpoint, that
Azure SRE Agent calls over the VNet:

- Data API builder runs on a Windows member server as a **gMSA** (Windows auth to SQL Server); on each SQL Server the
  gMSA has a login and `##MS_ServerPerformanceStateReader##` only. **No database and no object** is created on the SQL
  Servers.
- The agent calls it with its **managed identity**; Data API builder accepts only tokens for its own Entra app that
  carry the app role it requires (assignment required).
- It comes from an earlier private research project that proved the shape in a lab. This playbook makes it (a) a lab
  that can be rebuilt with one command when needed and (b) a released playbook like perfmon-blackbox: versioned, a zip
  as a GitHub release asset, CHANGELOG, a quick install in Turkish and English.
- Audience: a real adopter need and the blog.

## S2: plan gate (Emre via the vezir, 2026-10-17)

Step 1 is the scaffold (this folder) and an inventory and plan for Emre, kept in Drive (`files/sql-mcp/plan-v1.md`),
never in the repo. Nothing past step 1 (no code copied, no lab, no Azure call, no release) until Emre approves that
plan through the vezir.

## S3: plan v1 approved; lab21 approved but not yet cleared (Emre via the vezir, 2026-10-17)

Emre approved the inventory and plan v1 (Drive, `files/sql-mcp/plan-v1.md`) as recommended, except its question 5
(S11, open). In short, the plan is:

- **Inventory.** From the source project (read-only): the four install scripts (AD prep, SQL login, DAB install, DAB
  config with the placeholder-root layout and the 7 DMV views), the PowerShell 5.1 MCP client, the Entra block and the
  agent steps of its install guide, and the guide's content. Rewritten: the lab build, the tests, the package build, the
  quick install. Dropped: the phase-1 config generator, the VNet upgrade script, the anonymous test switch, the
  session helpers, the static-bearer and ARM-audience shapes (named in the guide, not shipped), the three DMFs that
  would need an object on SQL Server.
- **Masking.** Tenant, subscription, resource group, agent, managed identity, app, app role and service principal IDs,
  subnet ranges and IPs are parameters or read at run time. The MCP host is `vm1`; `sql1`, `sql2`, `dc` and the example
  domain `contoso.local` stay.
- **Lab.** A new lab, **lab21**, from the private lab template (one web member, two SQL members, the VNet-integrated
  agent), built by one command, tested end to end, torn down. Existing labs are never touched. The build pauses at
  one ready-made Entra command for an admin, then resumes.
- **DAB drift.** DAB is pinned (2.1.5 at the time of writing) with the SHA-256 of its zip. The placeholder root is
  re-tested after every DAB upgrade (T24); a local check compares the pin with the latest stable DAB release.
- **Release v1.0.0.** Tag `sql-mcp/v1.0.0`, asset `SqlMcp.zip` (deterministic, SHA-256 in README and CHANGELOG).
- **Tests.** Local L01–L04 (config generator, PowerShell 5.1 lint, deterministic package, DAB drift); lab T10–T25.

**lab21 is approved but not cleared.** No lab build and no Azure call until the vezir says lab21 is cleared (one more
question goes to Emre first). Repo-side work that needs no Azure may start.

## S4: the Entra step is run by Emre, in the lab as at an adopter (plan question 2)

The app registration, its app role and the role assignment to the agent's managed identity are created by
`package/admin/entra-setup.sh` (or `.ps1`), run by an admin with their own account: in the lab, Emre, at every lab
build. The lab service principal gets **no** directory rights.

## S5: a persistent lab app and user-assigned identity, after v1.0.0 (plan question 3)

After v1.0.0, the lab may get a persistent Entra app and a persistent user-assigned managed identity outside any lab
resource group (no cost), assigned the app role once, so that a rebuild needs no Entra step. v1.0.0 ships and is
tested with the agent's **system-assigned** identity (the proven path). The user-assigned path is proven in the lab
before it is documented as tested.

## S6: defaults (plan question 4)

App `sql-mcp-api`, app role `MCP.Read`, gMSA `gmsa-sqlmcp`, scheduled task `DAB-sqlmcp`, connector `sqlmcp`, port
5000, plain HTTP inside the VNet. HTTPS and an outbound proxy are documented as untested.

## S7: scale tooling stays test-only (plan question 6)

The alias switch of the config script and the scale measurement script live under `tests/lab/` as test tools, never
in the package. No scale test runs for v1.0.0.

## S8: a fresh-eyes install before v1.0.0 (plan question 7)

Before the release, a separate session installs from the README alone on lab21, before its teardown.

## S9: where the guides live (plan question 8)

The English adopter guide is the playbook `README.md` (with `docs/`). The quick install in Turkish and English is in
Drive (`files/sql-mcp/`), as for perfmon-blackbox.

## S10: on-premises is documented, not claimed as tested (plan question 9)

v1.0.0 says: tested on Azure VMs in the agent's VNet; on-premises (VPN or ExpressRoute, outbound 443 to Entra) is
documented and untested.

## S11: an agent skill in v1.0.0? (plan question 5; answered in S13)

Recommendation: no, a skill comes in v1.1.0 with its own tests. Emre asked what the skill would be; his answer is
pending through the vezir. Nothing skill-related is built until he answers.

## S12: repo-side rewrite of the source scripts (this session, 2026-10-17, under S3)

**Provenance.** Copied from the earlier private research project at commit `2153d05` (2026-10-04), then changed as
listed below. SHA-256 of each source file as copied:

| Source file | SHA-256 (as copied) | Becomes |
|---|---|---|
| `scripts/01-ad-prep.ps1` | `94bd412638e6f2ae50ee7cffeee8a47cec5d06b8123d5bcbd51125c6e16029d9` | `package/01-ad-prep.ps1` |
| `scripts/02-sql-login.sql` | `0eafa7019678120b2870e34812e1d83b2db4ecc27842085c031de3f63c11e2c8` | `package/02-sql-login.sql` |
| `scripts/03-dab-install.ps1` | `09ffb8caf6cc0cf22996d2b3f8b1cd571eb39c7904b0d5ff368d7f85feaf89ae` | `package/03-dab-install.ps1` |
| `scripts/04-dab-config.ps1` | `27d0a1e5ae0891c923593830309a0aeeb449d36afd6695575e1d1b923ba803b0` | `package/04-dab-config.ps1` |
| `scripts/mcp-call.ps1` | `3a21425c5eb833e718904d47514d63bee25502eb69f1911e433cab9ea01988c5` | `package/tools/mcp-call.ps1` |
| `docs/install-guide.en.md` (§7 Entra block and agent steps) | `883eb72b5c94596bb4848f93c68fa0c32920b35ad80369a1b422d6fb69001407` | `package/admin/entra-setup.{sh,ps1}`, `package/agent/connect-agent.{sh,ps1}` |

**Changes (the mask table of the plan applied):**

- **01-ad-prep.ps1:** the MCP host and gMSA names are parameters (`-McpHost` is required: the host's computer name).
  The KDS root key is created effective immediately (wait 10 h before step 3), or back-dated only with
  `-LabBackdateKdsKey`. The test user `mcp-tester` is **dropped**: in the production auth shape the host's own
  identity is refused a token (V5), so a Windows client user on the host has nothing to test.
- **02-sql-login.sql:** the login is the sqlcmd variable `$(GmsaLogin)` (`-v GmsaLogin=DOMAIN\gmsa-sqlmcp$`).
- **03-dab-install.ps1:** `-From` (the agent and VM subnets) is **required**, with no default range. The gMSA's
  domain is read from Active Directory. Port, task name and install root are parameters. The DAB zip is checked
  against a **pinned SHA-256** per version (2.1.5: the digest GitHub publishes for `dab_net10.0_win-x64-2.1.5.zip`);
  another version needs `-Sha256`.
- **04-dab-config.ps1:** production shape only: `-TenantId` and `-AppId` are required (v2 issuer, audience = app ID,
  only the app role may read). `-Servers`, `-Domain`, `-Role`, `-ConfigDir`, `-AllowedHosts` are parameters (the
  tenant is no longer patched in with `sed`). Existing JSON files are copied to a timestamped backup folder before
  they are overwritten. `-Anonymous` and `-Aliases` are **not** in the package (S7). The placeholder-root layout and
  the 7 views with all their columns and descriptions are unchanged.
- **entra-setup / connect-agent:** the guide's idempotent blocks as scripts. Inputs are the agent's resource ID, the
  app ID, the endpoint; the agent's identity is read from ARM, never written. `entra-setup` prints the app ID for the
  next step; it is run by an admin (S4). `connect-agent` keeps the agent's egress object and sets only
  `allowHttpMcpServerNetworkAccess = false`, then PUTs the connector.
- **Local tests** need PowerShell 7 on the authoring machine (`pwsh` on the PATH or `$PWSH`) for L01 and L02; the
  GitHub Ubuntu runner has it. Nothing is installed on a server for a test.
- **Found by L01 (2026-10-17):** under `powershell.exe -File`, a list parameter such as `-Servers sql1,sql2` arrives as
  ONE string. `03-dab-install.ps1` (`-From`) and `04-dab-config.ps1` (`-Servers`, `-AllowedHosts`) now split every
  list parameter on commas, so both `-File` and an interactive call work.
- **L02 lint profiles:** Windows Server 2016 and 2019 (PowerShell 5.1) only, no Windows 10 client profile: the MCP host
  is a Windows Server, and step 3 uses Server-only cmdlets (`Get-WindowsFeature`, `Install-WindowsFeature`).

## S13: the agent skill comes in v1.1.0 (Emre via the vezir, 2026-10-17; closes S11)

v1.0.0 ships without an agent skill: the entity and column descriptions in the DAB configuration are what the agent
reads. A skill (how to read the DMVs: drop benign waits, take two samples of cumulative counters, …) comes in
v1.1.0 with its own tests.

## S14: lab21 cleared (the vezir, 2026-10-17 07:20Z, on Emre's approval; lab SP secret rotated first)

lab21 is built now with `tests/lab/lab-up.sh` from the private lab template (latest tag v1.4.1), one web member (`vm1`)
and two SQL members, in the gitignored `.lab/sql-mcp/`. It is registered in the template's lab register in the same
commit as the build. Rules: every other lab and resource group is untouched; every lab run ends before 21:45Z (the
nightly stop); the lab SP gets no extra role without asking first (the connector PUT is the open question). The
Entra admin step (S4) is relayed to Emre through the vezir.

## S15: azd signs in through az; admin logins live outside the repo tree (the vezir, 2026-10-17)

- **azd uses az's login.** After the lab SP secret rotation, azd's own cached SP login was stale (`azd up` failed at
  once with AADSTS7000215; nothing was created). Instead of a new `azd auth login` (which would pass the secret on the
  command line), the repo's local azd config (`.azd-config`, shared with perfmon-blackbox sessions) is set to
  `auth.useAzCliAuth true`: azd takes its tokens from the az login of the same folder set (`.azure-cli`), which
  `cr-azlogin` keeps current. Undo: `direnv exec . azd config unset auth.useAzCliAuth`, then an SP `azd auth login`.
- **Admin logins are never in a repo tree,** not even a gitignored one. Emre's device-code login for the Entra step
  (S4) goes into `$HOME/.azure-sqlmcp-admin` (started by the vezir); the session runs `entra-setup.sh` with
  `AZURE_CONFIG_DIR` set to it, then `az logout` and deletes the folder.

## S16: the lab build reads as a rehearsal of the adopter guide (Emre via the vezir, 2026-10-17)

`lab-up.sh`'s phases are renamed and each one names the README install steps it runs:

| Was | English | Turkish | README install steps |
|---|---|---|---|
| phase A | **Lab build** | Lab ortamı + hazırlık | a stand-in adopter environment (the lab), then steps 1–3 |
| the Entra step | **Admin consent** | Admin onayı | step 4 (an Entra admin runs `entra-setup`) |
| phase B | **MCP connect** | MCP bağlantısı | steps 5–6 |

The flag for the last phase becomes `--connect --app-id <id>`; `--app-id <id>` alone stays as an alias, since the
record already refers to it. Done after the first lab21 test run, not during it.

## S17: lab21 run 1: T10–T24 all PASS; what the lab found (2026-10-17)

Run 1 (09:06–09:26Z): 11 of 15 passed at once; T12, T13, T15 and T22 failed on **test-side** expectations only and
passed after the fixes below (09:26–09:29Z). The playbook itself needed one fix.

- **Product fix (connect-agent):** the egress PATCH puts the agent into `InProgress` for a moment; a connector PUT
  right after it is refused (`OperationConflict`, "Agent must be in Succeeded state"). `connect-agent.sh/.ps1` now
  wait for `provisioningState Succeeded` before and after the PATCH (up to 10 min). `lab-up.sh` also printed "done"
  despite that failure (a pipe hid the exit code); it now stops.
- **The lab SP's existing rights are enough** for the egress PATCH and the connector PUT: no extra role was needed or
  granted (the open question of S14 is closed).
- **Test fixes:** lab command output carries Windows `\r` (now stripped in `common.sh`, T12); the task principal is
  stored without the domain and the firewall shows ranges as address/mask (T13 compares the account name and the
  networks); a connector GET returns `type`, `endpoint`, scope and header as null (T15 checks kind, auth type and
  state); `dab.log` names the failing **entity** (`sql2_…`), not the host (T22).
- **Facts seen:** the agent used `describe_entities` then `aggregate_records` for the session count (2; sqlcmd 3
  including itself) and matched sqlcmd's top wait on sql2. azd's cached SP login was stale after the secret rotation
  (S15).

## S18: lab21 is torn down today (Emre via the vezir, 2026-10-17 ~10:00Z, "önerdiğin gibi")

T25 runs now: `lab-down.sh --yes` (role assignments scoped in rg-lab21 first, then `azd down --purge --force`),
then the template's lab audit and its register row in one commit. The fresh-eyes install (S8) will rebuild a lab with
`lab-up.sh` when it is due. The Entra app `sql-mcp-api` is kept (no cost; its assignment goes with the agent's
identity). Other labs and resource groups are untouched.
- **Done (2026-10-17 09:46:40Z):** `lab-down.sh` finished (azd down 10m56s, Key Vault purged); T25 PASS (no
  resource group, 0 role assignments at or below its scope); the template's lab audit CLEAN; register row DOWN.
  Fixes found on the way: `lab-down.sh` listed role assignments with `--include-inherited false` (that flag takes no
  value) and with `--scope` only, which misses assignments on resources inside the group: it now uses `--all` with a
  scope filter. `azdv` (common.sh) returned azd's error text when a value was gone (azd prints errors on stdout): it
  now uses the exit code. No role assignment was left over.

## S19: release v1.0.0 now (Emre via the vezir, 2026-10-17, "YAYINLA")

- **What:** tag `sql-mcp/v1.0.0` on `main` and a GitHub release (not a pre-release) whose only asset is `SqlMcp.zip`,
  built by `package/build.sh 1.0.0` from the package files that lab21 tested: no file under `package/` changed after
  `85dafa8`, the commit the T10–T25 run used. Its SHA-256 is in the CHANGELOG, the README and the release notes.
- **Before the upload** (release assets bypass the git hooks, as for perfmon-blackbox P29/P66): every file extracted
  from the zip, and the release notes, pass `scripts/scrub-check.sh`. After it: the asset downloaded from the public
  URL must hash to the same SHA-256.
- **Not "Latest":** the repo has no multi-playbook convention yet (only perfmon-blackbox has releases); "Latest" is
  repo-wide, so sql-mcp is published with `--latest=false` and perfmon-blackbox v1.0.2 keeps the badge. A repo-wide
  rule for this belongs in `docs/decisions.md` if Emre wants one.
- **No preview, and the fresh-eyes install (S8) moves to after the release**, as perfmon-blackbox did (P66): its
  findings go into v1.0.x. The quick installs in Drive are updated to point at the tag.
