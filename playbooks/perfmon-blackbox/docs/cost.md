# Cost

> **Summary.** On an Azure VM the black box costs a few cents a month (storage); on an Arc-enabled server add
> Machine Configuration at USD 6.00 per server per month (unless your Arc servers are already covered, e.g. by a
> benefit that includes it). Per deployment, the private endpoint costs about USD 7.30 a month.
>
> Prices: Azure Retail Prices API (`prices.azure.com`), retail USD, queried 2026-10-11 (storage in Sweden Central).
> Draft until v1.0.0.

| Item | Price | Per server per month |
|---|---|---|
| Machine Configuration on an **Azure VM** | included | 0 |
| Machine Configuration on an **Arc-enabled server** ("Guest Configuration Policy/Server") | 6.00 USD / server / month | **6.00 USD** |
| Blob storage, Hot LRS | 0.0184 USD / GB / month | ≈ 0.01 USD (100 processes) … ≈ 0.03 USD (350 processes) |
| Write operations | 0.05 USD / 10,000 | < 0.01 USD (6 exports a day; one Put Blob each, or a few Put Block calls) |
| Private endpoint data processed | 0.01 USD / GB | < 0.01 USD |
| Private endpoint | 0.01 USD / hour | **≈ 7.30 USD per deployment** (shared by all servers) |

## Storage volume per server

A zipped capture costs about **1.9 KB per sample** at ~117 processes and 10 s (measured in the lab: CSV ≈ 12 KB per
sample, zip ≈ 1/8 of it). That is ≈ 16 MB a day and ≈ 0.5 GB held under the 30-day lifecycle rule. The volume grows
with the process count like the buffer does ([parameters.md](parameters.md)): about 3× at 350 processes (≈ 1.5 GB held,
≈ 0.03 USD a month). A shorter interval multiplies it (1 s = 10× the 10-s volume).

**Totals**: Azure VM ≈ 0.01–0.03 USD a month; Arc server ≈ 6.01–6.03 USD a month; plus ≈ 7.30 USD a month per
deployment. The SRE Agent's own usage (the analysis) is billed by the agent and not counted here.
