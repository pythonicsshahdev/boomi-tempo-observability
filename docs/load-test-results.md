# Load test results

Method: `scripts/loadtest.sh --synthetic` drives telemetrygen traces and metrics into the collector (traces to 4319, metrics to 4317), samples every container's memory every few seconds, then reports peak memory against the limit, restarts, OOM kills and volume sizes. Gate: any restart, OOM kill, or a container not running at the end fails the run. The machine is the Colima VM (16 GiB). Limits at the time: collector 256m, tempo 512m, prometheus 256m, grafana 384m.

Synthetic data is the fallback profile; a Boomi Load Testing Toolkit profile run against a Boomi API (real runtime telemetry) is still to do.

## Run 1: baseline, Tempo stack, 500 spans/s + 60 metrics/s, 300 s (2026-11-07)

Generated: 37,449 traces with 3 child spans each (about 500 spans/s) and 17,999 metrics. Gate: **passed**.

| container | peak MiB | limit MiB | restarts | OOM |
|---|---|---|---|---|
| collector | 72.8 | 256 | 0 | no |
| tempo | 386.5 | 512 | 0 | no |
| prometheus | 37.9 | 256 | 0 | no |
| grafana | 285.5 | 384 | 0 | no |

Volumes after the run: tempo-data 56,780 KiB, prometheus-data 15,772 KiB.

Observations:
- Tempo is the container to watch: it rose from about 103 MiB at the start to 386.5 MiB (75% of its limit) during the 5 minutes.
- Grafana sits at 285-306 MiB of 384 even when idle (tight, 74-80%).
- Collector and Prometheus have plenty of headroom.

## Starved-collector control (fails on purpose)

With the collector limited to 8 MB: 12 restarts in about 20 s, OOMKilled true, and the gate exits 1 naming the collector. A starved collector crash-loops (`restart: always` hides it from a casual `docker ps`), which is one plausible shape for the earlier unattributed crash.

## Run 2: 2x load, original limits (2026-11-07)

1,000 spans/s + 60 metrics/s, 300 s (71,743 traces with 3 child spans each). Gate: **failed**.

| container | peak MiB | limit MiB | restarts |
|---|---|---|---|
| collector | 75.1 | 256 | 0 |
| tempo | 507.4 | 512 | **2** |
| prometheus | 37.8 | 256 | 0 |
| grafana | 286.7 | 384 | 0 |

**First failure: Tempo**, at about 1,000 spans/s with a 512m limit. Tempo's memory scales with ingest rate; the collector, Prometheus and Grafana were never close.

## Run 3: 2x load, tuned limits (2026-11-07)

Same profile (71,895 traces). Tempo raised to 1g, Grafana to 512m (Task 12: tune limits before changing components). Gate: **passed**.

| container | peak MiB | limit MiB | restarts |
|---|---|---|---|
| collector | 80.4 | 256 | 0 |
| tempo | 519.4 | 1024 | 0 |
| prometheus | 37.6 | 256 | 0 |
| grafana | 480.0 | 512 | 0 |

Volumes after the three runs (cumulative): tempo-data 309,168 KiB, prometheus-data 15,988 KiB. The Tempo spike config keeps 1 hour of blocks.

Open: Grafana peaked at 94% of its limit in this run, up from about 75% in earlier runs, with no dashboard load. It was recreated just before the run, so this may be warm-up, but it is the next container likely to fail. Watch it, and raise it to 768m if it repeats.

## Comparison with the OpenSearch stack (same synthetic profiles, 2026-11-07)

The OpenSearch stack (OpenSearch with a 512 MB heap, Vector, OTel Collector, Prometheus, Grafana) has no container memory limits. Same machine, same telemetrygen profiles; metrics go to Vector, traces to its collector. Volume growth is measured before and after each run (the OpenSearch volume already held about 1.9 GB of older data, so only growth is comparable).

| profile | stack | gate | peak memory, sum of containers | disk growth |
|---|---|---|---|---|
| 500 spans/s, 300 s | Tempo (limits 256/512/256/384) | passed | about 783 MiB | about 56 MB (Tempo), under 1 MB (Prometheus) |
| 500 spans/s, 300 s | OpenSearch | passed | about 1,401 MiB | 142.5 MB (OpenSearch), 0.2 MB (Prometheus) |
| 1,000 spans/s, 300 s | Tempo, original limits | **failed** (Tempo restarted twice, 507/512 MiB) | n/a | about 145 MB |
| 1,000 spans/s, 300 s | Tempo, tuned (Tempo 1g, Grafana 512m) | passed | about 1,117 MiB (Grafana alone 480) | about 107 MB |
| 1,000 spans/s, 300 s | OpenSearch | passed | about 1,449 MiB | 285.7 MB (OpenSearch), 0.15 MB (Prometheus) |

Per container, OpenSearch peaked at 926-970 MiB, Vector about 33, collector about 70, Prometheus about 39, Grafana about 333. The Tempo stack's collector, Prometheus and Grafana are comparable; the difference is Tempo (386-519 MiB) against OpenSearch plus Vector (about 960-1,000 MiB).

What this says (synthetic load only; real Boomi load is probably lower and burstier):
- At 500 spans/s the Tempo stack used about 55% of the OpenSearch stack's memory and about 40% of its disk growth. The "lighter" estimate holds.
- At 1,000 spans/s OpenSearch was steady (about 970 MiB), while Tempo's memory scaled with the rate and ran out at 512 MB. Tempo needs a limit sized to the expected rate; OpenSearch's heap cap makes it less rate-sensitive.
- Neither stack was driven to its breaking point on the OpenSearch side. Memory and disk for a real Boomi runtime profile (toolkit against a Boomi API) are still to be measured.
- Tempo's disk figures depend on its retention (1 hour in the spike config) and compaction, so run-to-run deltas are noisy.

## Run 4: real runtime load through the Boomi Load Testing Toolkit (2026-11-07)

Load: toolkit profile `profiles/tempo-load-target.yaml` (5, 10, 20, 40, 10 transactions/s, 40 s each, 8 s warmup per step), run id 20261107-193845, through the Boomi API Gateway to the `TempoObs Load Target Listener` process on the local Docker Atom (one GET = one process execution = 5 spans). The stack was sampled for the whole run (`scripts/loadtest.sh --duration 330` started together with the toolkit). Limits: collector 256m, tempo 1g, prometheus 256m, grafana 512m. Stack gate: **passed**, no restarts, no OOM kills.

| container | peak MiB | limit MiB | restarts |
|---|---|---|---|
| collector | 77.4 | 256 | 0 |
| tempo | 420.2 | 1024 | 0 |
| prometheus | 24.8 | 256 | 0 |
| grafana | 264.5 | 512 | 0 |

Disk growth: tempo-data +42,284 KiB, prometheus-data +40 KiB.

Client side (toolkit): the Atom saturated near 27 transactions/s.

| step | target TPS | achieved TPS | avg ms | p95 ms | error rate |
|---|---|---|---|---|---|
| 1 | 5 | 4.96 | 82 | 163 | 0.0% |
| 2 | 10 | 9.96 | 90 | 173 | 0.0% |
| 3 | 20 | 19.88 | 140 | 242 | 0.2% |
| 4 | 40 | **27.76** | 445 | 921 | 0.9% |
| 5 | 10 | 9.52 | 135 | 402 | 0.0% |

Observations:
- The stack was not the bottleneck. The Atom tops out at about 27 executions/s, roughly 135 spans/s, about a quarter of the 500 spans/s the synthetic baseline passed with the same stack. Peak memory here (Tempo 420 MiB, collector 77 MiB) is in line with the synthetic 500 spans/s run.
- **Toolkit counts and trace counts agree.** In the run window (19:38-19:44) Tempo holds 2,850 `Execute process` traces for the listener. The toolkit reports 2,122 samples in its table, plus about 680 warmup requests it excludes ((5+10+20+40+10) x 8 s) = about 2,802. The difference is under 2%. This is evidence for the Stage 3 correlation check (JMeter request count vs span count), including that warmup requests must be counted on the trace side.
- **Failures are visible in traces.** The toolkit logged 17 failed requests; Tempo has 15 traces with `execution.success = "false"` (the rest, HTTP 400 "Unable to create new index segment", fail before an execution starts). The failures themselves come from the Atom: 500 "Unable to create new index segment / Error storing data, file not found" under the Atom's data directory, which is a macOS bind mount through Lima. Disk space and inodes were fine. Concurrent file creation on that mount is the likely cause (not verified). The errors start at 20 TPS and grow at 40 TPS.
- **The gateway sent no telemetry of its own.** Its OpenTelemetry settings point at this stack (`host.docker.internal:4318`, traces `:4320`), yet only the Atom's service name appeared in Tempo. Not diagnosed.
- A first toolkit run (19:31) was only partly sampled because the sampler was started too early; its numbers are not used.
