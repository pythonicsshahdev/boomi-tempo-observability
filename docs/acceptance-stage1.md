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

## Still to do (needs a process run on the runtime)

- Tempo has no traces from the runtime yet, only the smoke test's. The Tempo panels (throughput, root span percentiles, executions per second, step boxplot) need a deployed process to run.
- Record the `span.runtime.nodeId` values once traces arrive, and whether they match anything in Prometheus.
- Check whether the Metrics and Logs sections of the Boomi Observability page override the global endpoint (they were collapsed in the screenshot).
