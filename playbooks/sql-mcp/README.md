# sql-mcp: let Azure SRE Agent read SQL Server DMVs, read-only, over your VNet

> Not an official Microsoft product. Working and versioned, no support promise. See the
> [repo README](../../README.md).

**Status: in development, not released.** Nothing here is ready to deploy yet.

## What it will be

- A **read-only MCP server** for SQL Server dynamic management views (waits, performance counters, memory, sessions,
  requests, query stats), built on [Data API builder](https://learn.microsoft.com/azure/data-api-builder/)'s MCP
  endpoint, running on a Windows member server.
- Data API builder connects to each SQL Server as a **gMSA** that has a login and
  `##MS_ServerPerformanceStateReader##` only. **No database and no object** is created on the SQL Servers.
- **Azure SRE Agent** calls it over the VNet with its **managed identity**. Data API builder accepts only tokens for
  its own Entra app that carry the required app role, so no secret is stored anywhere.

The adopter guide, the release package and the tests come with the first release.
