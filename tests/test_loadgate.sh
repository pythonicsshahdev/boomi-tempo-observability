#!/bin/bash
# Fails-on-purpose check for the load gate: with the collector starved to 8 MB,
# loadtest.sh must exit 1 and name the collector.
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
export PROMETHEUS_PORT=${PROMETHEUS_PORT:-9091}
cat > results/_starve.yml <<'YML'
services:
  collector:
    mem_limit: 8m
YML
docker-compose -f docker-compose.yml -f results/_starve.yml up -d collector >/dev/null 2>&1
out=$(bash scripts/loadtest.sh --synthetic --duration 20 --rate 2000 2>&1); rc=$?
docker-compose up -d collector >/dev/null 2>&1
rm -f results/_starve.yml
echo "$out" | tail -12
assert_eq 1 "$rc" "gate exits 1 when the collector is starved"
assert_eq 1 "$(echo "$out" | grep -c -i 'GATE FAILED.*collector')" "gate names the collector"
