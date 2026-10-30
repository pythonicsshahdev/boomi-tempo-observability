# Stage 1 acceptance on the real runtime

Runtime: `SHAH_MACOS_LOCAL_DOCKER_RUNTIME_03292026` (local Docker runtime). Observability settings: global endpoint `http://host.docker.internal:4317`, traces override `http://host.docker.internal:4319`. No Boomi setting was changed to use this stack.

## Findings so far (checked 2026-10-29, `tests/check_panels.sh boomi-loadtest`)

**Metrics: confirmed on real Boomi data.**
- Prometheus has `job="SHAH_MACOS_LOCAL_DOCKER_RUNTIME_03292026"` series, so resource `service.name` becomes `job` as the spike predicted.
- The unit-suffixed names the spike predicted are present from the real runtime: `jvm_heap_current_bytes`, `jvm_heap_max_bytes`, `jvm_nonheap_current_bytes`, `jvm_gc_count`, `jvm_gc_time_milliseconds`, `jvm_cpu_time_nanoseconds`, `jvm_runtime_uptime_milliseconds`, `jvm_threads_active`, `jvm_file_descriptor_count`, plus the `execution_*` and `runtime_*` families.
- 15 of 24 panels returned non-zero data with no process running; zero query errors.

**`node` label: absent on this runtime.**
- The real series carry no `jvm_id` label (the only `jvm_id` value in Prometheus came from the synthetic smoke test). This is consistent with the earlier finding that `jvm.id` exists only on molecules. A local Atom is not a molecule.
- The panels still work, because `jvm_id=~".*"` also matches series that have no `jvm_id`. The `node` variable is empty and legends that use `{{jvm_id}}` are blank. Per-node views need a molecule to verify.

**Control (fails on purpose): `--service nosuchservice` returns 0 panels with data and 0 errors.** A missing service shows no data, not zeros.

## After a process run (checked 2026-10-30, process `Employee XML to JSON Demo - Test`)

**Traces: confirmed on real Boomi data, after one fix.**
- Tempo holds spans from the runtime (root span name `Submit process execution`, `service.name` = the runtime id as above). `span.process.name` values include `Employee XML to JSON Demo - Test` and `Employee XML to JSON Demo`.
- **Finding: the spans carry `runtime.id` and `runtime.name`, but no `runtime.nodeId`.** (`runtime.id` = `8ad9cbe3-a691-434f-a105-e2619dab47df`, the Atom id.) The example dashboard filtered trace panels on `span.runtime.nodeId`, an attribute that exists only on its cluster runtime. In TraceQL a filter on a missing attribute matches nothing (a negative regex `!~` also returns 0), so every trace panel read zero: 8 root spans without the filter, 0 with it.
- **Fix:** removed ` && span.runtime.nodeId =~ "${node:regex}"` from all 9 TraceQL queries. The `node` variable still filters the Prometheus panels. Cost: on a molecule the trace panels are not filtered by node, and a per-node trace filter would need an attribute that exists there (not verifiable here).
- After Grafana reloaded the dashboard (restart needed; it did not pick up the edited file on its own): **20 of 24 panels return data, 0 query errors.** The panels still at zero are legitimately empty on an idle healthy runtime (runtime state flags are all false, queued/running executions, failed executions, failures per second).
- Tempo's TraceQL metrics only accept a range of up to 3 hours here (`metrics query time range exceeds the maximum allowed duration of 3h0m0s`), so the dashboard's default `now-1h` works but a 6h or 24h range will error on the Tempo panels.

**Control (fails on purpose): `--service nosuchservice` returns 0 panels with data and 0 errors.**

## Still open

- Whether the Metrics and Logs sections of the Boomi Observability page override the global endpoint (collapsed in the screenshot; not checked).
- `jvm_id` and `span.runtime.nodeId` do not exist on a local Atom, so the shared node variable could not be checked against a molecule.
