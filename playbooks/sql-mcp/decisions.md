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

## S11: an agent skill in v1.0.0? OPEN (plan question 5)

Recommendation: no, a skill comes in v1.1.0 with its own tests. Emre asked what the skill would be; his answer is
pending through the vezir. Nothing skill-related is built until he answers.
