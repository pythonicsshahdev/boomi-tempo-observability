# boomi-tempo-observability

Boomi runtime telemetry on **Prometheus + Tempo + Grafana**: one OpenTelemetry Collector receives what a Boomi runtime exports over OTLP, traces go to Tempo, metrics to Prometheus, and Grafana shows a runtime-health dashboard.

It is the lighter sibling of the OpenSearch-based stack ([`otel-fanout-quickstart`](https://github.com/pythonicsshahdev/otel-fanout-quickstart), [`observability-stack`](https://github.com/pythonicsshahdev/observability-stack)). Neither is better; they differ:

| | This repo (Tempo) | OpenSearch stack |
|---|---|---|
| Traces | Tempo (TraceQL) | OpenSearch |
| Metrics | Prometheus | OpenSearch |
| Logs | accepted and **discarded** (not stored in v1) | stored and searchable |
| Fan-out to Splunk, Datadog, etc. | no | yes |

You switch between the two with `scripts/switch-stack.sh tempo|opensearch|status` (see Switching below). They use the same OTLP ports, so your Boomi settings do not change. Anything Boomi sends while neither is up is lost.

## Quick start

Needs Docker with `docker-compose` (hyphenated), `curl`, `jq`, `unzip`, and a Docker VM with at least 4 GiB.

```bash
bash scripts/install.sh
```

The script checks prerequisites (it changes nothing if one is missing), downloads the Grafana ECharts plugin, refuses to start if a port is already held (and names the holder), starts the stack, and waits until it is healthy. Then open Grafana at http://localhost:3000 (login `admin` / `admin`, a local demo default; change it before exposing the port) and the dashboard **Boomi Runtime — Load Test**.

If something else already uses port 9090 (for example the Boomi Load Testing Toolkit's Prometheus), run `export PROMETHEUS_PORT=9091` first. Prefer to see every step? Follow [`docs/manual-setup.md`](docs/manual-setup.md).

In AtomSphere (runtime > Manage > Observability), point the Global Endpoint at `http://host.docker.internal:4317` (a runtime in Docker on the same machine) and override Traces with port `4319`. The stack answers on 4317/4318 and 4319/4320. The HTTP ports (4318, 4320) go through a small nginx proxy that repairs a Boomi API Gateway bug (it sends JSON bodies labeled as protobuf); see [`docs/gateway-otlp-content-type-bug.md`](docs/gateway-otlp-content-type-bug.md). To get the gateway's telemetry, point its OpenTelemetry settings at `http://host.docker.internal:4318` (traces `:4320`).

## Switching between this stack and the OpenSearch stack

```bash
scripts/switch-stack.sh status        # prints: tempo | opensearch | none | both
scripts/switch-stack.sh tempo         # stops the OpenSearch stack, starts this one, waits until healthy
scripts/switch-stack.sh opensearch    # stops this stack, starts the OpenSearch stack, waits until healthy
```

Containers and data volumes are kept either way, so nothing is lost; telemetry Boomi sends while neither stack is up is. The script refuses (changing nothing) if the OpenSearch folder is missing. It looks for it in `~/Documents/OTEL/vector_simplified`; set `OPENSEARCH_STACK_DIR` if yours is elsewhere. This stack's Prometheus is published on `PROMETHEUS_PORT` (default 9091 in the script, since 9090 is often taken by the Boomi Load Testing Toolkit). Optional shell aliases: `alias tempo-stack='~/path/to/boomi-tempo-observability/scripts/switch-stack.sh tempo'` and the same for `opensearch`.

## What you see

- **Prometheus panels:** JVM heap, GC, CPU, threads, file descriptors, uptime, execution queue, platform messaging.
- **Tempo panels:** throughput, root-span p50/p95/p99, executions per second by process, failures, and a per-step duration boxplot.
- The collector extracts `consumerId` and ten similar fields from Notify messages into span attributes.

Known limits, from running it against a real runtime (details in [`docs/acceptance-stage1.md`](docs/acceptance-stage1.md)):
- A local Atom has no `jvm_id` metric label, so the node variable is empty (only molecules have it).
- Trace panels are not filtered by node: real spans carry `runtime.id`/`runtime.name`, not `runtime.nodeId`.
- Tempo metrics queries accept at most a 3-hour range here; the dashboard's default is 1 hour.
- Boomi's span status is always Ok, so traces cannot show failures by status.

## Checking a toolkit run against the traces

```bash
python3 -m blt check --run-id <toolkit run id> --route /ws/rest/<api>/<path> \
    --jtl-dir <toolkit folder>/test-plans/results
```

Compares the number of requests JMeter sent with the number of traces on that route in the run's window, on whichever stack is running (detected), and prints `match`, `mismatch` or `uncorrelated` (exit code 0, 1, 2). Design and evidence: [`docs/stage3-checker-design.md`](docs/stage3-checker-design.md). Python tests: `python3 -m pytest`.

## Tests

```bash
export PROMETHEUS_PORT=9091   # only if 9090 is taken
bash tests/test_configs.sh && bash tests/test_compose.sh && bash tests/test_smoke.sh
bash tests/check_panels.sh boomi-loadtest      # every dashboard panel through /api/ds/query
```

`tests/test_portguard.sh` and `tests/test_install.sh` stop and restart the stack.

## Dashboard spike result

Checked on Grafana **13.2.4** (pinned): the Grafana v2 dashboard schema loads from file provisioning as-is, and the `volkovlabs-echarts-panel` plugin works. Grafana's own plugin installer fails on networks that intercept TLS (`x509: certificate signed by unknown authority`), so `scripts/fetch-plugins.sh` downloads it on the host and the compose file mounts it read-only.

## Status

Working: the stack, install and manual guide, the runtime dashboard on real Boomi data, and a load test with a restart/OOM gate (`scripts/loadtest.sh`, results in [`docs/load-test-results.md`](docs/load-test-results.md): about 55% of the OpenSearch stack's memory at 500 spans/s, but Tempo needs a 1 GiB limit at 1,000 spans/s). Planned: a load-to-trace correlation checker that reads from the separate Boomi Load Testing Toolkit (a JMeter-based project, not part of this repo), and ports of the other OpenSearch dashboards. Logs (Loki) would be an optional later extra.

## License

MIT, see [LICENSE](LICENSE).
