#!/bin/bash
cd "$(dirname "$0")/.." || exit 1
. scripts/lib.sh
PROM=${PROMETHEUS_PORT:-9090}
bad=0
for p in 4317 4318 4319 4320 3000 3200 "$PROM"; do
  h=$(port_holder "$p")
  [ -n "$h" ] && { echo "port $p is held by $h" >&2; bad=1; }
done
if [ "$PROM" != 9090 ]; then
  h=$(port_holder 9090)
  [ -n "$h" ] && echo "note: port 9090 is held by $h; Prometheus publishes on $PROM instead" >&2
fi
[ "$bad" = 1 ] && exit 2
[ "$1" = "--check-only" ] && exit 0
docker-compose up -d
