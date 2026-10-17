# CLAUDE.md: sql-mcp (rules of this playbook only)

Shared rules: `../../CLAUDE.md`. Read `HANDOVER.md`, then `decisions.md`, before any work here.

- **Plan gate (R11, R20).** Until Emre approves the inventory and plan (Drive, `files/sql-mcp/`), this folder holds
  only the scaffold: no code, no lab, no Azure call.
- **Source is read-only.** The earlier SQL MCP research project is private and lives outside this repo. Copy from it,
  never write to it, and never name it here; every copied file gets a provenance line in `decisions.md` (source
  commit, SHA-256 as copied).
- **Nothing lab- or tenant-specific in the repo.** Tenant, subscription, app, role, service principal and managed
  identity IDs, subnet ranges, domain and host names are parameters with placeholders (`<app-id>`,
  `<agent-subnet-cidr>`, …). The scrub check refuses GUIDs and private IPv4 addresses; fix the text, do not allow-list.
- **Machine names in the repo:** the MCP host is `vm1`, the SQL Servers `sql1`, `sql2`, the domain controller `dc`.
- **Existing labs are never touched.** This playbook tests only in its own lab, built from the private lab template
  for it and registered there; any other lab or resource group is out of bounds.
- **Entra objects are an admin step.** The app registration, its app role and the role assignment need directory
  rights the lab service principal must not have: they are a ready-made command an admin runs, in the lab as at an
  adopter.
- **Windows PowerShell 5.1 on servers.** Every script that runs on an adopter's server is 5.1 compatible and installs
  no other runtime (Data API builder's self-contained build is the product itself, not a runtime).
