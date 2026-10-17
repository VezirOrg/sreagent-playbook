# sql-mcp tests

`tests/run.sh <ID>` from the playbook folder, or `tests/run.sh local` for L01–L04. Synthetic values only (IDs are
made up at run time). The full list, lab tests included, is in `../docs/tests.md` once the lab tests exist.

| ID | What | Needs |
|---|---|---|
| L01 | `04-dab-config.ps1`: placeholder root, one file per server, 7 views, only the app role reads, v2 issuer, backup on rerun, `-AppId` required | PowerShell 7 |
| L02 | every `.ps1` passes the Windows PowerShell 5.1 compatibility rules (PSScriptAnalyzer 1.23.0, saved to a temp folder) | PowerShell 7, PSGallery |
| L03 | `package/build.sh` is deterministic and ships exactly the package files, with no GUID or private IPv4 | Python 3 |
| L04 | the pinned Data API builder is the latest stable and its SHA-256 matches GitHub's digest | GitHub API |
