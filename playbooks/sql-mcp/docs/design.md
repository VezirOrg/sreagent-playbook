# sql-mcp: design and evidence

Why the playbook is built the way it is, and what each claim rests on. Legend: ✅ proven in a lab (the earlier research
lab on 2026-10-04 and/or this playbook's lab21 on 2026-10-17, test IDs in [tests.md](tests.md)) · 📄 documented (Microsoft
Learn or the Data API builder source), not tested.

## Goal and constraints

- The SRE Agent answers questions about SQL Server **performance state** (waits, counters, memory, sessions, requests,
  query stats) on several servers.
- **Nothing is created on the SQL Servers:** no database, no user, no view, no procedure. A server login and one
  server-role membership are the whole footprint ✅ (T12).
- **Read only**, no free SQL, no secret stored anywhere, no public endpoint.
- Works where the servers are: Azure VMs in a VNet ✅; on-premises over VPN or ExpressRoute 📄.

## Why Data API builder, and its limits

Data API builder (DAB) serves configured database objects as an API, and since 2.x as an **MCP endpoint**. It needs no
code of its own: every tool call becomes a `SELECT` on a configured view ✅. What follows from that:

| Can | Cannot |
|---|---|
| DMV **views** as entities ✅ (T14) | DMV **functions** (`dm_exec_sql_text`, `dm_db_index_physical_stats`, `dm_io_virtual_file_stats`): DAB fails to start ✅; a wrapper view would be an object on SQL Server |
| filter, sort, select, first N, aggregates ✅ (T19) | free SQL: there is no "run a query" tool ✅ |
| | views with a `sql_variant` column (`sys.configurations`, `sys.dm_server_registry`, …): DAB 2.1.5 fails at startup, even with the column left out of `fields` 📄 |
| | `SERVERPROPERTY`, `@@VERSION`: functions 📄 |

Any entity that fails stops **all** of DAB ✅. Every column is listed in `fields` with descriptions for the ones agents
filter on, because `describe_entities` shows only what is listed ✅ (T14); the agent then finds the right entity by
itself, `describe_entities` first ✅ (T19).

## Identity towards SQL Server: a gMSA

DAB runs as a **group managed service account** under a scheduled task (DAB is not a Windows service), so it reaches
SQL Server with Windows authentication over Kerberos and no password is stored ✅ (T13). The gMSA gets a login and
`##MS_ServerPerformanceStateReader##` (SQL Server 2022+): performance DMVs only, no table data, no change, no security
DMVs ✅ (T12). Older versions need `VIEW SERVER STATE`, which is broader 📄 ([operations.md](operations.md#sql-server-versions)).

## Identity towards DAB: the agent's managed identity and an app role

The options that were weighed:

| Shape | Verdict |
|---|---|
| Anonymous inside the VNet | rejected: anything in the VNet could read |
| A static bearer token in the connector | works ✅, but expires (~24 h) and is a secret to rotate by hand |
| ARM audience (any ARM token of the tenant) | works ✅, but every identity in the tenant could get such a token |
| OAuth sign-in (MCP-spec OAuth) | rejected: needs a public HTTPS endpoint, DAB serves no OAuth discovery metadata, and the token would be a user's, not the agent's |
| **The agent's managed identity + an Entra app with an app role, assignment required** | **chosen** ✅ |

How the chosen shape locks:

1. **Entra:** the app (`sql-mcp-api`) requires assignment, so only identities assigned its role `MCP.Read` get a token
   for it. The MCP host's own identity is refused (AADSTS501051) ✅ (T17). Without "assignment required", Entra would
   issue app-only tokens without a `roles` claim to any app that asks 📄 (Learn, client-credentials flow).
2. **DAB:** `jwt.audience` = the app ID and the **v2** issuer. With v2 tokens `aud` is the app ID (a GUID), not
   `api://<appId>` ✅ (T16). DAB validates the signature with Entra's keys, fetched at runtime over outbound 443 (no
   offline mode) 📄 (DAB source).
3. **The role header:** every entity is readable only by `MCP.Read`. A valid token without `X-MS-API-ROLE: MCP.Read`
   acts as `authenticated`, which sees nothing ✅ (T18). A token without the role in its `roles` claim gets 403 📄.

The connector uses the agent's **system-assigned** managed identity: "Managed identity" on a Streamable-HTTP connector
writes `identity: system`, `authType: AzureARM` and a free-text scope, and the platform fetches and renews the token ✅
(T16, T19). Custom headers are flat keys in the connector's `extendedProperties` ✅ (T18). Managed-identity tokens are
cached for up to ~24 h per resource, so the role is assigned before the agent's first token request 📄 (Learn, managed
identity best practices). A user-assigned identity is possible 📄 and planned after v1.0.0.

The Entra objects (one app, one service principal, one assignment) need directory rights. They are a ready-made,
idempotent command for an admin (`admin/entra-setup`), in the lab as at an adopter ✅ (T15).

## Network

DAB listens on plain HTTP, port 5000, on all interfaces; Windows Firewall lets in only the agent's subnet (and any test
subnet) ✅ (T13). The agent's egress is the VNet with "Remote MCP server access" off, so its MCP calls come from its
delegated subnet ✅ (T20); the host name resolves through the VNet's DNS. HTTPS is not needed inside the VNet; whether
the agent trusts a private CA is untested 📄.

On-premises: the agent's VNet reaches the network over VPN or ExpressRoute, and the host needs outbound 443 to Entra
for the signing keys (a proxy goes into the task's environment) 📄. An on-premises host has no managed identity, which
does not matter: the token always comes from the agent.

## Configuration layout and its failure mode

DAB reads every entity's schema at startup. If any listed SQL Server is unreachable then, DAB does not start at all and
does not recover by itself; the scheduled task's restart setting never fires because DAB's exit is recorded as
"completed" ✅ (T22). A server that dies while DAB runs only fails its own entities, which recover ✅. So:

- **one file per server** behind a **placeholder root** (DAB 2.1.5 refuses a root without a data source; the
  placeholder has an unresolvable name and no entities, so it is never contacted) ✅ (T24);
- a server is taken out by renaming its file to `.off`: a listed file that is missing is **skipped silently** ✅ (T21),
  which is why [operations.md](operations.md#take-a-server-out) has a check for it;
- recovery is **manual by design** (no automatic retry), and servers are grouped per DAB by failure domain and
  maintenance window, at most 25 per DAB (measured: capacity is not the limit) ✅.

Both DAB behaviours the layout relies on (the placeholder and the silent skip) are re-tested after every DAB upgrade:
the version and the SHA-256 of its zip are pinned ✅ (L04, T24).

## What v1.0.0 does not cover

Server configuration and the DMV functions (above); SQL Server < 2022 (documented grant, untested); on-premises hosts,
HTTPS and a proxy (documented, untested); real distinct servers at scale and concurrent questions (not measured); an
agent skill that teaches the agent how to read DMVs (v1.1.0, decisions S13).
