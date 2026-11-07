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
