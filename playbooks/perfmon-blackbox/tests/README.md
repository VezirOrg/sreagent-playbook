# tests: perfmon-blackbox

Planned; not built yet (the design and the test plan wait for approval). The plan is
[../docs/test-plan.md](../docs/test-plan.md): stage tests T01–T16 (lab, one command each:
`tests/run.sh <ID> [machine]`) and local tests L01–L06 (no Azure, synthetic data only, run in CI).

Fixtures go in `fixtures/synthetic/`. Real or masked data never goes here.
