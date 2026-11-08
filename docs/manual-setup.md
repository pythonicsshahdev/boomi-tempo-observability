# Manual setup: Prometheus + Tempo + Grafana for Boomi runtime telemetry

This is the step-by-step version of `scripts/install.sh`. Do it by hand if you want to see each piece, or if the script does not fit your machine. Every step ends with a check; do not continue until it passes. Several steps say "copy from the repo" (the long collector transforms, `tempo.yaml`, the dashboard JSON, `docker-compose.yml`, the Grafana provisioning files, and the scripts and tests used in steps 6 and 9), so clone this repo next to your working folder first and copy from it.

What you get: Boomi sends OTLP to one OpenTelemetry Collector. Traces go to Tempo, metrics to Prometheus, and logs are accepted and discarded (this stack does not store logs; use the OpenSearch stack if you need Boomi logs in Grafana). Grafana shows the Boomi Runtime dashboard.

## 0. Prerequisites

You need Docker with `docker-compose` (hyphenated; the `docker compose` plugin form may not work on your machine), `curl`, `jq` and `unzip`, and a Docker VM with at least 4 GiB.

```bash
docker-compose version && curl --version | head -1 && jq --version && unzip -v | head -1
docker info --format '{{.MemTotal}}'      # at least 4294967296
```

## 1. Free the ports

The stack publishes these host ports: 4317, 4318, 4319, 4320 (OTLP), 3000 (Grafana), 3200 (Tempo), 9090 (Prometheus). Only one OTLP receiver can own 4317-4320, so stop any other stack that uses them (for the OpenSearch stack: `docker-compose stop` in its folder; `docker-compose start` brings it back later).

```bash
for p in 4317 4318 4319 4320 3000 3200 9090; do docker ps --filter publish=$p --format "$p held by {{.Names}}"; done
```

Nothing should print. If something holds 9090 and you cannot stop it, run Prometheus on another port by exporting `PROMETHEUS_PORT=9091` in every shell you use for this stack.

## 2. Create the folder layout

```bash
mkdir -p boomi-runtime-observability/{config,dashboards,targets,grafana/provisioning/datasources,grafana/provisioning/dashboards,grafana/plugins}
cd boomi-runtime-observability
```

## 3. Collector config (`config/collector.yaml`)

The collector listens for OTLP on 4317 (gRPC) and 4318 (HTTP). Boomi's settings usually point traces at 4319 and everything else at 4317; the compose file maps both pairs of host ports onto the same receiver, so you never change Boomi when you switch stacks.

Take the `processors:` block from this repo's `config/collector.yaml` (it holds the Boomi-specific transforms: duration in milliseconds, numeric step counts, and extraction of `consumerId` and ten similar fields from the Notify message), then add the receivers, exporters and pipelines around it:

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }
# ...processors: block from the repo goes here...
exporters:
  otlp/tempo: { endpoint: "tempo:4317", tls: { insecure: true } }
  prometheus: { endpoint: "0.0.0.0:8889" }
  nop: {}
extensions:
  health_check: { endpoint: 0.0.0.0:13133 }
service:
  extensions: [health_check]
  telemetry:
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus: { host: "0.0.0.0", port: 8888 }
  pipelines:
    traces:  { receivers: [otlp], processors: [transform/boomi_numeric, transform/boomi_usf_fields, batch], exporters: [otlp/tempo] }
    metrics: { receivers: [otlp], processors: [batch], exporters: [prometheus] }
    logs:    { receivers: [otlp], exporters: [nop] }
```

The `logs` pipeline matters: without it the collector answers Boomi's log exports with `Unimplemented` and Boomi's exporter reports errors.

Check:

```bash
docker run --rm -v "$PWD/config":/c otel/opentelemetry-collector-contrib validate --config /c/collector.yaml && echo valid
```

### 3b. The OTLP/HTTP shim (only needed for the Boomi API Gateway)

The gateway posts OTLP/HTTP with a protobuf content type but a JSON body, and the collector rejects it with HTTP 400. Copy `config/shim/otlp-http-shim.conf` from the repo into `config/shim/`. The compose file (step 7) runs it as the `otlp-http-shim` service, which publishes 4318 and 4320 and rewrites the content type when the body starts with `{`. See `docs/gateway-otlp-content-type-bug.md`. A runtime that uses gRPC on 4317 or 4319 does not need it.

## 4. Tempo config (`config/tempo.yaml`)

Pin Tempo 2.9.0; `latest` is v3 and this config has not been tried on it. Copy the config from `config/tempo.yaml` in the repo. The two parts that must be present are `metrics_generator.storage.path` and the `local-blocks` processor under `overrides`; without them the dashboard's TraceQL metric panels fail with `500 ... empty ring`.

```bash
grep -c local-blocks config/tempo.yaml     # 1
```

## 5. Prometheus config (`config/prometheus.yml`)

```yaml
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: collector-metrics
    honor_labels: true
    static_configs:
      - targets: ['collector:8889']
  - job_name: jmeter-targets
    honor_labels: true
    file_sd_configs:
      - files: ['/etc/prometheus/targets/*.json']
        refresh_interval: 5s
```

`honor_labels: true` is what keeps the runtime's `service.name` as the `job` label. Check (a warning that `/etc/prometheus/targets/*.json` does not exist is normal: that folder only fills when a JMeter run writes a target file):

```bash
docker run --rm --entrypoint promtool -v "$PWD/config":/c prom/prometheus check config /c/prometheus.yml
```

## 6. Grafana: datasources, dashboard provider, plugin

Copy `grafana/provisioning/datasources/datasources.yml` and `grafana/provisioning/dashboards/dashboards.yml` from the repo (datasource uids must be `tempo` and `prometheus`, because the dashboard refers to them by those names), and `dashboards/boomi-runtime-load-test.json`.

The dashboard's step boxplot needs the `volkovlabs-echarts-panel` plugin. Grafana's own installer fails on networks that intercept TLS (`x509: certificate signed by unknown authority`), so download it on your machine instead:

```bash
bash scripts/fetch-plugins.sh
ls grafana/plugins/volkovlabs-echarts-panel/plugin.json
```

## 7. Compose file and start

Copy `docker-compose.yml`. It sets a memory limit and `restart: always` on every container, pins Grafana 13.2.4 and Tempo 2.9.0, and publishes Prometheus on `${PROMETHEUS_PORT:-9090}`.

```bash
docker-compose config -q && docker-compose up -d
```

Check (give Tempo about 20 seconds):

```bash
curl -s localhost:3200/ready; curl -s localhost:${PROMETHEUS_PORT:-9090}/-/ready; curl -s localhost:3000/api/health | jq -r .version
```

## 8. Point Boomi at the stack

In AtomSphere, open the runtime, Manage > Observability. Set the Global Endpoint to `http://host.docker.internal:4317` (a runtime in Docker on the same machine) or `http://<host-address>:4317` otherwise, and override Traces with port 4319 the same way. No authentication. If your runtime already points there for another stack, change nothing.

## 9. Check the data

After a minute with the runtime running:

```bash
curl -sG localhost:${PROMETHEUS_PORT:-9090}/api/v1/query --data-urlencode 'query=jvm_heap_current_bytes' | jq '.data.result | length'   # at least 1
bash tests/check_panels.sh boomi-loadtest      # lists every panel with its sample count
```

Open `http://localhost:3000` (admin / admin), then the dashboard "Boomi Runtime — Load Test". Run a deployed process once; the Tempo panels (throughput, root span percentiles, step boxplot) fill after the first execution.

A local Atom has no `jvm_id` label (only molecules do), so the node variable is empty and legends that use it are blank. The panels still work.

## 10. Switching to the OpenSearch stack and back

Boomi data sent while neither stack is up is lost, so avoid running processes during a switch.

```bash
docker-compose down                         # this stack (volumes are kept)
cd <vector_simplified folder> && docker-compose start    # the OpenSearch stack
```

To come back: `docker-compose stop` in the OpenSearch folder, then `scripts/start.sh` here. `scripts/start.sh` refuses to start and names the holder if a port is still taken.
