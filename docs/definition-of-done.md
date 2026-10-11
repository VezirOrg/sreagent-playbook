# Definition of done (every playbook release)

A playbook release `<name>/vX.Y.Z` is done when **all** of the following hold. The playbook's
`docs/test-plan.md` maps each item to its tests; a release note quotes the evidence (run date, lab, result).

## 1. Every stage green on a fresh lab (the centre)

- The playbook's full stage test suite passes **end to end on a freshly built lab**, ending with the analysis
  stage (for perfmon-blackbox: the agent's report from the latest zip, scored).
- Each test runs with **one command** in the lab and prints PASS/FAIL with its evidence.
- No stage is skipped or marked "manual" without Emre's word written in the playbook's `decisions.md`.

## 2. README-only fresh-eyes deploy

Someone (a fresh session with no access to the record) deploys the playbook into a clean lab **from the README
alone** and gets the stage suite green. Every gap found is fixed in the README before release.

## 3. Security

- No secrets in the repo or its history: `scripts/scrub-check.sh` clean on the tree and on the release range,
  with the denylist present.
- Scrub clean: no real name anywhere (code, docs, tests, commit messages).
- Storage is private (no anonymous access, no shared-key access, network restricted) and checked by a test.
- Least privilege: every identity has only the rights its step needs, written down in the design and checked
  by a test (including a negative test where it matters, e.g. a machine cannot write into another machine's
  prefix).

## 4. Cost

The cost **per server per month** (and the fixed cost per deployment) is written in the README, with the price
source (Azure Retail Prices API query or pricing page) and date.

## 5. CI green

The repo's GitHub Actions workflow passes on the release commit (scrub check without denylist, static checks,
local tests on synthetic data, and the package build where CI can run it).

## 6. Tag and release

Tag `<name>/vX.Y.Z` on the release commit, GitHub Release with the package zip attached as an asset and its
SHA-256 in the release notes, `CHANGELOG.md` updated.

## 7. Lab cleaned or registered

The lab is torn down with leftover checks, **or** it stays up with a registered reason in the private lab template's
`docs/labs.md` ("why up · until whose word"). No orphan.

## 8. Record

The playbook's `HANDOVER.md` says the release is out, with the tag. (The root `HANDOVER.md` stays an index and
holds no playbook status, R12.)
