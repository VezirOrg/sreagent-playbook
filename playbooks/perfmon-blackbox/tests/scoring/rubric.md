# T16 rubric: the agent's report on the latest zip, scored against the planted ground truth

Deterministic: `score.py <report.txt> <truth.json> [--zip <blob name>]` applies the fixed rules below to the report
text and prints the points per item. Ground truth = `make-trouble.ps1`'s `truth.json` (synthetic load, times in the
machine's local time). Rule 6 and the VERDICT CEILING are scored as written in SKILL.md today; the rubric takes no side
on OPEN-1 (P8); OPEN-2 is closed for v1.0.0 (P34): no short stalls are planted.

| # | Item | Points | Rule |
|---|---|---|---|
| C1 | latest zip named | 10 | the report contains the zip file name the agent fetched (`--zip`), or `<machine>_<from>_<to>` of it |
| C2 | host | 5 | the machine name appears |
| C3 | time range | 5 | the first and last sample times (HH:MM) of the capture appear |
| P1 | leak found | 30 | a line names `bbleak` and a growth (MB/h or GB/h) within ±40 % of the planted rate |
| P2 | CPU burst found | 30 | a line (or the line after) names CPU and a time within ±2 min of the planted start, and `bbcpu` appears in the report |
| V1 | verdict words | 5 | "critical"/"severe" never appears on the same line as the stalls or the leak alone |
| N1 | nothing invented | 5 | none of: commit near limit, PTE exhaustion, paging file filling, disk nearly full, a network or disk-latency problem (none is planted, P43) |
| R1 | causal claims tested | 5 | every line with "caused by", "because" or "drives" has a `LINK:` line in the report (or the report has none of those words) |
| R2 | no raw data | 5 | no line holds more than 30 comma- or pipe-separated numbers |

Total 100. **Pass = score ≥ 80 and P1, P2 found** (test plan T16; only memory and CPU are planted, P43). The short stalls of OPEN-2 are not planted or scored in v1.0.0 (decisions P34).
