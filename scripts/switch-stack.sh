#!/bin/bash
# switch-stack.sh tempo | opensearch | status
# Boomi allows one OTLP endpoint per signal, so only one of the two stacks can own ports 4317-4320.
# Switching stops the running one (containers and data volumes are kept), starts the other, and waits
# until it is healthy. Telemetry Boomi sends while neither stack is up is lost.
#   OPENSEARCH_STACK_DIR  folder holding the OpenSearch stack's docker-compose.yml (default: ~/Documents/OTEL/vector_simplified)
#   PROMETHEUS_PORT       host port for this stack's Prometheus (default 9091; 9090 is often taken by the Load Testing Toolkit)
usage() { echo "usage: $0 tempo|opensearch|status" >&2; exit 2; }
[ $# -eq 1 ] || usage
HERE=$(cd "$(dirname "$0")/.." && pwd)
OS_DIR=${OPENSEARCH_STACK_DIR:-$HOME/Documents/OTEL/vector_simplified}
export PROMETHEUS_PORT=${PROMETHEUS_PORT:-9091}

tempo_up()      { [ -n "$(docker ps -q --filter 'name=^boomi-tempo-collector-1$')" ]; }
opensearch_up() { [ -n "$(docker ps -q --filter 'name=^opensearch$')" ]; }
current() {
  if tempo_up && opensearch_up; then echo both
  elif tempo_up; then echo tempo
  elif opensearch_up; then echo opensearch
  else echo none; fi
}
wait_for() {  # wait_for <label> <url> ...
  local label=$1; shift
  for i in $(seq 1 60); do
    ok=1; for u in "$@"; do curl -sf -m 3 "$u" >/dev/null 2>&1 || ok=0; done
    [ $ok = 1 ] && { echo "$label is healthy"; return 0; }
    sleep 3
  done
  echo "$label did not become healthy in 3 minutes; check: docker ps -a" >&2; return 1
}

case $1 in
  status) echo "$(current)"; exit 0 ;;
  tempo)
    echo "switching to the Tempo stack (was: $(current))"
    if opensearch_up; then (cd "$OS_DIR" && docker-compose stop) || exit 1; fi
    bash "$HERE/scripts/start.sh" || exit $?
    wait_for "Tempo stack" "localhost:3200/ready" "localhost:3000/api/health" "localhost:$PROMETHEUS_PORT/-/ready" ;;
  opensearch)
    [ -f "$OS_DIR/docker-compose.yml" ] || { echo "OpenSearch stack folder not found: $OS_DIR (set OPENSEARCH_STACK_DIR)" >&2; exit 2; }
    echo "switching to the OpenSearch stack (was: $(current))"
    if tempo_up; then bash "$HERE/scripts/stop.sh" || exit 1; fi
    (cd "$OS_DIR" && { docker-compose start >/dev/null 2>&1 || docker-compose up -d; }) || exit 1
    wait_for "OpenSearch stack" "localhost:9200/_cluster/health" "localhost:3000/api/health" ;;
  *) usage ;;
esac
