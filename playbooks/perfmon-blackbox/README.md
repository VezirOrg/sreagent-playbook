# perfmon-blackbox

A **black-box PerfMon recorder** for Windows servers, for Azure SRE Agent.

> Not an official Microsoft product. Working and versioned, no support promise. See the
> [repo README](../../README.md).

**Status: in design. There is no release yet, and nothing here is ready to deploy.** This README becomes the
adopter guide with the first release (`perfmon-blackbox/v1.0.0`).

## What it will do

- An **Azure Machine Configuration** package keeps a PerfMon Data Collector Set running on every targeted server
  (also right after every reboot).
- Once a day the server exports the day's capture (CSV, zipped) to **your private storage account**, with **its own
  managed identity**, into **its own folder**; it cannot write anywhere else.
- Two Azure Policy definitions: one for **Azure VMs**, one for **Azure Arc-enabled servers**. Assign the one(s) you
  need.
- An **Azure SRE Agent skill** (`perfmon-triage`) finds the latest capture of a server, converts it and analyses it,
  and posts its findings in the agent thread.

The design is in [docs/design.md](docs/design.md), the tests in [docs/test-plan.md](docs/test-plan.md).

## What is here today

- `skill/perfmon-triage/`: the analysis skill v2.0 (SKILL.md, `perfq.py`, `perfmon_csv_to_sqlite.py`). It reads a
  PerfMon CSV today; reading the latest capture from storage comes in v2.1.
- `scripts/deploy-skill.sh`: create or update the skill on an agent through the data plane API (dry run by
  default).
- `lab-tools/perfmon_mask_csv.py`: replaces names in a PerfMon CSV from a private mapping and fails on any name of
  a private denylist. A test-side tool; never part of the package or the skill.

## Cost

Written here per server and per deployment before the first release.
