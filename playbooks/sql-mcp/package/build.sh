#!/bin/sh
# build.sh <version> <out.zip>: build the release package SqlMcp.zip, deterministically (same input = same SHA-256:
# sorted entries, fixed timestamps and modes). Prints the SHA-256. The zip is a GitHub Release asset, never committed.
set -eu
version="${1:?usage: build.sh <version> <out.zip>}"; out="${2:?usage: build.sh <version> <out.zip>}"
here=$(cd "$(dirname "$0")" && pwd)
python3 -I - "$here" "$version" "$out" <<'PY'
import hashlib, re, sys, zipfile
src, version, out = sys.argv[1:]
FILES = ['01-ad-prep.ps1', '02-sql-login.sql', '03-dab-install.ps1', '04-dab-config.ps1', 'tools/mcp-call.ps1',
         'admin/entra-setup.sh', 'admin/entra-setup.ps1', 'agent/connect-agent.sh', 'agent/connect-agent.ps1']
dab = re.search(r"\[string\]\$Version = '([^']+)'", open(f'{src}/03-dab-install.ps1').read()).group(1)
readme = f"""sql-mcp {version}: a read-only SQL Server DMV MCP server for Azure SRE Agent
Data API builder {dab} (pinned with its SHA-256 in 03-dab-install.ps1)

Order (the README of the playbook has the details and the checks):
  1  01-ad-prep.ps1          on a domain controller (Domain Admin)
  2  02-sql-login.sql        on each SQL Server (sysadmin)
  3  03-dab-install.ps1      on the MCP host (local admin)
  4  admin/entra-setup.*     an Entra admin, once
  5  04-dab-config.ps1       on the MCP host, then start the scheduled task
  6  agent/connect-agent.*   someone with SRE Agent Administrator on the agent
tools/mcp-call.ps1: a minimal MCP client for checks (Windows PowerShell 5.1).

Not an official Microsoft product. MIT licence, the sreagent-playbook authors.
"""
entries = [(f, open(f'{src}/{f}', 'rb').read()) for f in FILES] + [('README.txt', readme.encode())]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, data in sorted(entries):
        zi = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        zi.external_attr = (0o755 if name.endswith('.sh') else 0o644) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(zi, data.replace(b'\r\n', b'\n'))
print(f'{out}: {len(entries)} files, SHA-256 {hashlib.sha256(open(out, "rb").read()).hexdigest().upper()}')
PY
