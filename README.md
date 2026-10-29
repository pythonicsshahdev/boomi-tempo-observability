# Boomi runtime observability on Prometheus + Tempo + Grafana

Work in progress. Design: `docs/superpowers/specs/2026-10-24-prometheus-tempo-standalone-design.md` in the `vector_simplified` repo.

## Dashboard spike result (Task 6)

Checked on Grafana **13.2.4** (pinned in `docker-compose.yml`):

- The Boomi Runtime dashboard (Grafana **v2** dashboard schema) loads from file provisioning as-is. The Kubernetes-style API reports `storedVersion: v2` and `conversion.failed: false`. No fallback to the v1 schema is needed.
- The `volkovlabs-echarts-panel` plugin (7.2.5) registers. Grafana's own installer fails on networks that intercept TLS (`x509: certificate signed by unknown authority`), so `scripts/fetch-plugins.sh` downloads it on the host and the compose file mounts it read-only. No fallback panel is needed.
- Not yet checked: that the boxplot panel actually renders data (Task 7, on a real runtime).
