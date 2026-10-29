#!/bin/bash
# Installs and starts the Prometheus + Tempo + Grafana stack.
# Changes nothing if a prerequisite is missing.
missing=""
for t in docker docker-compose curl jq unzip; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
[ -n "$missing" ] && { echo "missing prerequisite(s):$missing" >&2; exit 2; }
d=${0%/*}; [ "$d" = "$0" ] && d=.
cd "$d/.." || exit 1
docker info >/dev/null 2>&1 || { echo "Docker is not running" >&2; exit 2; }
mem=$(docker info --format '{{.MemTotal}}')
need=$(( ${MIN_VM_GIB:-4} * 1073741824 ))
[ "$mem" -ge "$need" ] || { echo "Docker VM has $((mem / 1073741824)) GiB; need at least ${MIN_VM_GIB:-4}" >&2; exit 2; }
bash scripts/fetch-plugins.sh >/dev/null || exit 1
bash scripts/start.sh || exit $?
PROM=${PROMETHEUS_PORT:-9090}
for i in $(seq 1 40); do
  if curl -sf localhost:3200/ready >/dev/null && curl -sf "localhost:$PROM/-/ready" >/dev/null && curl -sf localhost:3000/api/health >/dev/null; then
    echo "stack is healthy: Grafana http://localhost:3000 (admin/admin), Prometheus :$PROM, Tempo :3200"
    exit 0
  fi
  sleep 3
done
echo "stack did not become healthy; run: docker-compose ps" >&2
exit 1
