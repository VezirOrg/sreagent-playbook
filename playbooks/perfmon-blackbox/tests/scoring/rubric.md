# T16 rubric: the agent's report on the latest zip, scored against the planted ground truth

Deterministic: `score.py <report.txt> <truth.json> [--zip <blob name>]` applies the fixed rules below to the report
text and prints the points per item. Ground truth = `make-trouble.ps1`'s `truth.json` (synthetic load, times in the
machine's local time). Rule 6 and the VERDICT CEILING are scored as written in SKILL.md today; the rubric takes no side
on OPEN-1/OPEN-2 (P8): the stalls are scored as **found**, never by their verdict word.

| # | Item | Points | Rule |
|---|---|---|---|
| C1 | latest zip named | 5 | the report contains the zip file name the agent fetched (`--zip`), or `<machine>_<from>_<to>` of it |
| C2 | host | 5 | the machine name appears |
| C3 | time range | 5 | the first and last sample times (HH:MM) of the capture appear |
| P1 | leak found | 15 | a line names `bbleak` and a growth (MB/h or GB/h) within ±40 % of the planted rate |
| P2 | CPU burst found | 15 | a line (or the line after) names CPU and a time within ±2 min of the planted start, and `bbcpu` appears in the report |
| P3 | disk episode found | 15 | a line names disk/latency/LogicalDisk and a time within ±2 min of the planted start |
| P4 | NIC burst found | 10 | a line names network/NIC/Bytes Total and a time within ±2 min of the planted start |
| P5 | stalls found | 10 | a line names a short/recurring stall (or 30-s CPU spikes) and at least one planted stall time ±2 min |
| V1 | verdict words | 5 | "critical"/"severe" never appears on the same line as the stalls or the leak alone |
| N1 | nothing invented | 5 | none of: commit near limit, PTE exhaustion, paging file filling, disk nearly full, link saturated without the NIC burst time |
| R1 | causal claims tested | 5 | every line with "caused by", "because" or "drives" has a `LINK:` line in the report (or the report has none of those words) |
| R2 | no raw data | 5 | no line holds more than 30 comma- or pipe-separated numbers |

Total 100. **Pass = score ≥ 80 and P1–P5 all found** (test plan T16).
