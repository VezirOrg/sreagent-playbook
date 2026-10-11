# Changelog: perfmon-blackbox

Tags: `perfmon-blackbox/vX.Y.Z`. The package zip of each release is a GitHub Release asset.

## Unreleased

- 2026-10-11: playbook created. Design and test plan drafted for approval. Skill v2.0, `deploy-skill.sh` and the
  CSV masker copied in verbatim (provenance in `decisions.md` P7).
- 2026-10-11: design and test plan rev 2 (P11–P15): Emre's 36 counters as a sanitized template, binary circular
  log with `MaxSizeMB` (default 512) on both policies, export around the circular file, buffer-hour estimate.
- 2026-10-11: P16–P19: lab18 measurement (partial), counter groups G1–G3, interval parameter, capacity check; PLAN-OK
  for design rev 3 (defaults 10 s / 512 MB / export 4 h).
