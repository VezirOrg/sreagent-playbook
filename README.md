# sreagent-playbook

Reference implementations ("playbooks") for [Azure SRE Agent](https://learn.microsoft.com/azure/sre-agent/).
Each playbook is a working, tested and versioned solution you can deploy and adapt.

> **Not an official Microsoft product.** This is a community repository. The playbooks work and are versioned,
> but there is **no support promise**: use them at your own risk, review them before you deploy them, and test
> them in your own environment first.

## Playbooks

| Playbook | What it does |
|---|---|
| [`perfmon-blackbox`](playbooks/perfmon-blackbox/) | A black-box PerfMon recorder on Windows servers (Azure VMs and Azure Arc-enabled servers), deployed with Azure Machine Configuration; daily exports to a private storage account; an SRE Agent skill analyses the latest capture of a machine. |
| [`sql-mcp`](playbooks/sql-mcp/) | A read-only MCP server for SQL Server dynamic management views (Data API builder, Windows auth with a gMSA, no object created on the SQL Servers) that Azure SRE Agent calls over the VNet with its managed identity. |

Each playbook has its own README (how to deploy), CHANGELOG and tests; its releases are listed under
[Releases](../../releases).

## Releases

Every playbook is released on its own, with a tag `<playbook>/vX.Y.Z` (for example `perfmon-blackbox/v1.0.0`).
A release's deployable package (for example a Machine Configuration `.zip`) is attached to the GitHub Release as
an asset; it is never committed to the repository.

## Guides

The step-by-step guides and the story behind each playbook are on the blog,
[sreagent.emreguclu.io](https://sreagent.emreguclu.io). Each post links to the release tag it describes.

## Data

The tests in this repository use **synthetic data only**. No real or masked capture from any real environment is
in this repository.

## License

Code: [MIT](LICENSE), copyright the sreagent-playbook authors. The blog posts are licensed separately
(CC BY 4.0) and live on the blog, not here.
