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
